import AVFoundation
import CoreImage
import Foundation
import Photos
import UIKit

/// Drives a two-camera `AVCaptureMultiCamSession`: live preview for both
/// feeds plus split / picture-in-picture / dual-file recording.
final class DualCameraController: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureMultiCamSession()

    /// Preview layers are owned here so SwiftUI can host them directly and
    /// reposition them per `CaptureMode` without reconfiguring the session.
    let backPreviewLayer = AVCaptureVideoPreviewLayer()
    let frontPreviewLayer = AVCaptureVideoPreviewLayer()

    @Published private(set) var isMultiCamSupported = AVCaptureMultiCamSession.isMultiCamSupported
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    /// True right after a lens starts/switches, until its auto-exposure
    /// settles. Recording/photo capture are blocked meanwhile so the dark
    /// exposure-ramp frames never end up in a saved clip.
    @Published private(set) var isWarmingUp = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var availableCameras: [CameraOption] = []
    @Published private(set) var backCameraID: String?
    @Published private(set) var frontCameraID: String?
    @Published private(set) var lastCaptureURL: URL?
    @Published private(set) var lastCaptureIsVideo = true
    @Published private(set) var lastCaptureThumbnail: UIImage?
    @Published private(set) var lastError: String?

    @Published var mode: CaptureMode = .pip

    /// When true the two feeds swap roles: the secondary lens becomes the
    /// main / top feed and the primary becomes the overlay / bottom feed.
    @Published private(set) var isSwapped = false

    /// Recording resolution tier. Changing it reconfigures the active formats.
    @Published private(set) var quality: VideoQuality = .hd

    /// Whether the requested 4K format was actually achievable on both lenses.
    @Published private(set) var fourKAvailable = true

    /// Recording frame rate. Changing it reconfigures the active formats.
    @Published private(set) var frameRate: FrameRate = .fps30

    /// Whether the requested frame rate was actually achievable on both lenses
    /// at the current quality (60fps × 4K MultiCam is model-dependent).
    @Published private(set) var fpsAchieved = true

    /// Live zoom factor of the back lens, driven by pinch and preset taps.
    @Published private(set) var currentZoomFactor: CGFloat = 1

    /// True while the capture session is interrupted (another app took the
    /// camera, or a phone call). Cleared automatically when it ends.
    @Published private(set) var isInterrupted = false

    /// Mirrors ProcessInfo.thermalState so the UI can warn when hot.
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    /// 竖横同拍 — when on (composite modes only) each clip is written twice:
    /// once portrait, once landscape.
    @Published var dualOrientation = false

    /// Back-camera zoom/lens presets (.5× / 1× / 2× / 长焦) for the chosen front pair.
    @Published private(set) var zoomPresets: [ZoomPreset] = []
    @Published private(set) var activeZoom: ZoomPreset?

    /// 手电筒 — continuous torch on the back lens, used as recording fill light.
    /// Cycles 关(.off) → 自动(.auto) → 常亮(.on), mirroring the system camera.
    @Published private(set) var torchMode: AVCaptureDevice.TorchMode = .off
    @Published private(set) var isTorchAvailable = false

    /// 计时器 — seconds to count down before recording actually starts.
    @Published var recordDelaySeconds = 0
    @Published private(set) var countdownRemaining: Int?

    private let sessionQueue = DispatchQueue(label: "dualcamera.session")
    private let dataQueue = DispatchQueue(label: "dualcamera.data")

    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var micInput: AVCaptureDeviceInput?

    private let backVideoOutput = AVCaptureVideoDataOutput()
    private let frontVideoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?

    private var backDataConnection: AVCaptureConnection?
    private var frontDataConnection: AVCaptureConnection?

    /// Set on the data queue by `capturePhoto()`; consumed by the very next
    /// synchronized frame pair, then cleared.
    private var photoCaptureArmed = false

    // Track device orientation so preview stays upright and recordings are
    // captured in the orientation the phone is held at.
    private var backRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var frontRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservations: [NSKeyValueObservation] = []

    private var exposureObservations: [NSKeyValueObservation] = []
    private var warmupTimeoutTask: Task<Void, Never>?

    private let recorder = DualStreamRecorder()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    private var recordingStart: Date?
    private var durationTimer: Timer?

    private var notificationObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        backPreviewLayer.videoGravity = .resizeAspectFill
        frontPreviewLayer.videoGravity = .resizeAspectFill
        backPreviewLayer.setSessionWithNoConnection(session)
        frontPreviewLayer.setSessionWithNoConnection(session)
        // We manage AVAudioSession ourselves (bluetooth mic, background-music
        // mixing) instead of letting the capture session overwrite it.
        session.automaticallyConfiguresApplicationAudioSession = false
        // Needed so UIDevice.current.orientation actually updates; used below
        // to ignore rotation updates while the phone is lying flat.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        registerLifecycleObservers()
        cleanupStaleCaptures()
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Interruptions, errors, thermal

    /// Watches for the events the system camera handles gracefully and we
    /// previously ignored: another app grabbing the camera, phone calls,
    /// runtime session errors, and thermal pressure.
    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        notificationObservers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isInterrupted = true
                // Finish the file cleanly instead of leaving a corrupt clip.
                if self.isRecording { self.stopRecording() }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
                self?.isInterrupted = false
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
                guard let self else { return }
                if let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError {
                    self.report(error.localizedDescription)
                }
                // Media-services resets stop the session; try to bring it back.
                self.sessionQueue.async {
                    if !self.session.isRunning {
                        self.session.startRunning()
                        let running = self.session.isRunning
                        DispatchQueue.main.async { self.isRunning = running }
                    }
                }
            },
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                // Incoming call while recording: save what we have.
                if self.isRecording { self.stopRecording() }
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let state = ProcessInfo.processInfo.thermalState
                self.thermalState = state
                // At critical pressure, stop recording so the clip is saved
                // before the system kills the camera outright.
                if state == .critical && self.isRecording {
                    self.stopRecording()
                }
            }
        ]
    }

    /// Configures the shared audio session for video recording: bluetooth
    /// microphones allowed, and the user's background music keeps playing
    /// instead of being killed the moment the camera opens.
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            // Not fatal: capture still works with the default session.
            report(LocalizationManager.shared.t(.errMicUnavailable))
        }
    }

    // MARK: - Discovery

    /// Physical lenses we expose. TrueDepth is intentionally excluded: on iPhone
    /// it is the same physical sensor as the front wide camera, so offering both
    /// lets the user pick the same camera twice and crashes MultiCam.
    private let multiCamDeviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera
    ]

    /// Sets of device IDs that MultiCam can run simultaneously. A pair is only
    /// valid if both IDs appear together in one of these sets.
    @Published private(set) var compatibleSets: [Set<String>] = []

    /// Lists the back lenses and the front (selfie) camera available for selection.
    func discoverCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: multiCamDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        let options = discovery.devices
            .filter { $0.position == .back || $0.position == .front }
            .map { device in
                CameraOption(
                    id: device.uniqueID,
                    displayName: CameraOption.displayName(for: device),
                    position: device.position,
                    deviceType: device.deviceType
                )
            }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position {
                    return lhs.position == .back
                }
                return lhs.displayName < rhs.displayName
            }

        let sets = discovery.supportedMultiCamDeviceSets.map { Set($0.map(\.uniqueID)) }

        DispatchQueue.main.async {
            self.availableCameras = options
            self.compatibleSets = sets
            if self.backCameraID == nil {
                self.backCameraID = options.first { $0.position == .back }?.id
            }
            if self.frontCameraID == nil {
                self.frontCameraID = options.first { $0.position == .front }?.id
            }
        }
    }

    /// True when the two cameras can run together in a MultiCam session.
    func areMultiCamCompatible(_ id1: String, _ id2: String) -> Bool {
        guard id1 != id2 else { return false }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: multiCamDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )
        return discovery.supportedMultiCamDeviceSets.contains { set in
            let ids = Set(set.map(\.uniqueID))
            return ids.contains(id1) && ids.contains(id2)
        }
    }

    // MARK: - Configuration

    func configure(backID: String?, frontID: String?) {
        sessionQueue.async {
            self.configureLocked(backID: backID, frontID: frontID)
        }
    }

    private func configureLocked(backID: String?, frontID: String?) {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            self.report(LocalizationManager.shared.t(.errMultiCamUnsupported))
            return
        }

        let wasRunning = session.isRunning
        if wasRunning { session.stopRunning() }

        session.beginConfiguration()

        rotationObservations.forEach { $0.invalidate() }
        rotationObservations.removeAll()
        backRotationCoordinator = nil
        frontRotationCoordinator = nil

        session.connections.forEach { session.removeConnection($0) }
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let backDevice = device(for: backID, fallback: .back),
              let frontDevice = device(for: frontID, fallback: .front) else {
            session.commitConfiguration()
            report(LocalizationManager.shared.t(.errNoCamerasFound))
            return
        }

        guard areMultiCamCompatible(backDevice.uniqueID, frontDevice.uniqueID) else {
            session.commitConfiguration()
            DispatchQueue.main.async { self.isRunning = false }
            report(LocalizationManager.shared.t(.errIncompatiblePair))
            return
        }

        do {
            let backInput = try AVCaptureDeviceInput(device: backDevice)
            let frontInput = try AVCaptureDeviceInput(device: frontDevice)
            guard session.canAddInput(backInput), session.canAddInput(frontInput) else {
                session.commitConfiguration()
                report(LocalizationManager.shared.t(.errCannotAddInput))
                return
            }
            session.addInputWithNoConnections(backInput)
            session.addInputWithNoConnections(frontInput)
            self.backInput = backInput
            self.frontInput = frontInput

            let backResult = applyBestFormat(to: backDevice, quality: quality, fps: frameRate)
            let frontResult = applyBestFormat(to: frontDevice, quality: quality, fps: frameRate)
            let requestedQuality = quality
            DispatchQueue.main.async {
                self.fourKAvailable = requestedQuality != .uhd4k || (backResult.widthOK && frontResult.widthOK)
                self.fpsAchieved = backResult.fpsOK && frontResult.fpsOK
            }

            applyMacroFocusIfNeeded(to: backDevice)
            let torchAvailable = backDevice.hasTorch && backDevice.isTorchAvailable
            DispatchQueue.main.async {
                self.isTorchAvailable = torchAvailable
                self.torchMode = .off
            }

            backDataConnection = try connectCamera(input: backInput, device: backDevice, previewLayer: backPreviewLayer, output: backVideoOutput, mirror: backDevice.position == .front)
            frontDataConnection = try connectCamera(input: frontInput, device: frontDevice, previewLayer: frontPreviewLayer, output: frontVideoOutput, mirror: frontDevice.position == .front)

            configureAudioSession()
            configureAudio()

            session.commitConfiguration()

            setupRotationTracking(backDevice: backDevice, frontDevice: frontDevice)

            synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [backVideoOutput, frontVideoOutput, audioOutput])
            synchronizer?.setDelegate(self, queue: dataQueue)

            session.startRunning()
            beginWarmup(backDevice: backDevice, frontDevice: frontDevice)

            let backID = backDevice.uniqueID
            let frontID = frontDevice.uniqueID
            let (presets, active) = buildZoomPresets(frontID: frontID, currentBackID: backID)
            DispatchQueue.main.async {
                self.backCameraID = backID
                self.frontCameraID = frontID
                self.zoomPresets = presets
                self.activeZoom = active
                self.isRunning = self.session.isRunning
                self.lastError = nil
            }
        } catch {
            session.commitConfiguration()
            report(LocalizationManager.shared.t(.errConfigFailed, error.localizedDescription))
        }
    }

    @discardableResult
    private func connectCamera(
        input: AVCaptureDeviceInput,
        device: AVCaptureDevice,
        previewLayer: AVCaptureVideoPreviewLayer,
        output: AVCaptureVideoDataOutput,
        mirror: Bool
    ) throws -> AVCaptureConnection? {
        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position).first else {
            throw NSError(domain: "DualCamera", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video port for \(device.localizedName)."])
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
        if session.canAddConnection(previewConnection) {
            session.addConnection(previewConnection)
            applyOrientation(previewConnection, mirror: mirror)
        }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { return nil }
        session.addOutputWithNoConnections(output)

        let dataConnection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(dataConnection) else { return nil }
        session.addConnection(dataConnection)
        applyOrientation(dataConnection, mirror: mirror)
        // Stabilize the recorded frames (preview stays unstabilized, like the
        // system camera — stabilized preview would feel laggy). `.auto` lets
        // the system pick the best mode the active format supports.
        if dataConnection.isVideoStabilizationSupported {
            dataConnection.preferredVideoStabilizationMode = .auto
        }
        return dataConnection
    }

    /// Observes each camera's horizon-level rotation so the preview layers stay
    /// upright as the phone turns. Capture rotation is locked at record start.
    private func setupRotationTracking(backDevice: AVCaptureDevice, frontDevice: AVCaptureDevice) {
        rotationObservations.forEach { $0.invalidate() }
        rotationObservations.removeAll()

        let backCoordinator = AVCaptureDevice.RotationCoordinator(device: backDevice, previewLayer: backPreviewLayer)
        let frontCoordinator = AVCaptureDevice.RotationCoordinator(device: frontDevice, previewLayer: frontPreviewLayer)
        backRotationCoordinator = backCoordinator
        frontRotationCoordinator = frontCoordinator

        applyPreviewAngle(backCoordinator.videoRotationAngleForHorizonLevelPreview, isBack: true)
        applyPreviewAngle(frontCoordinator.videoRotationAngleForHorizonLevelPreview, isBack: false)

        rotationObservations = [
            backCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                self?.applyPreviewAngle(angle, isBack: true)
            },
            frontCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] _, change in
                guard let angle = change.newValue else { return }
                self?.applyPreviewAngle(angle, isBack: false)
            }
        ]
    }

    private func applyPreviewAngle(_ angle: CGFloat, isBack: Bool) {
        DispatchQueue.main.async {
            // While the phone is lying flat (pointed at ceiling/floor) gravity
            // can't tell portrait from upside-down, so the rotation coordinator's
            // angle becomes unreliable and can flip 180° on the slightest nudge.
            // Ignore updates in that pose and keep the last known-good angle.
            guard UIDevice.current.orientation.isValidInterfaceOrientation else { return }

            let layer = isBack ? self.backPreviewLayer : self.frontPreviewLayer
            guard let connection = layer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
        }
    }

    /// Blocks recording/photo capture until both lenses' auto-exposure has
    /// settled (with a timeout safety net), so the initial dark exposure-ramp
    /// — most visible on the front lens — never lands inside a saved clip.
    private func beginWarmup(backDevice: AVCaptureDevice, frontDevice: AVCaptureDevice) {
        exposureObservations.forEach { $0.invalidate() }
        exposureObservations.removeAll()
        warmupTimeoutTask?.cancel()

        DispatchQueue.main.async { self.isWarmingUp = true }

        let checkSettled = {
            if !backDevice.isAdjustingExposure && !frontDevice.isAdjustingExposure {
                DispatchQueue.main.async { self.isWarmingUp = false }
            }
        }

        exposureObservations = [
            backDevice.observe(\.isAdjustingExposure, options: [.new]) { _, _ in checkSettled() },
            frontDevice.observe(\.isAdjustingExposure, options: [.new]) { _, _ in checkSettled() }
        ]

        warmupTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.isWarmingUp = false }
        }

        checkSettled()
    }

    private func configureAudio() {
        guard let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else {
            report(LocalizationManager.shared.t(.errMicUnavailable))
            return
        }
        session.addInputWithNoConnections(input)
        micInput = input

        if let port = input.ports(for: .audio, sourceDeviceType: mic.deviceType, sourceDevicePosition: mic.position).first,
           session.canAddOutput(audioOutput) {
            session.addOutputWithNoConnections(audioOutput)
            let connection = AVCaptureConnection(inputPorts: [port], output: audioOutput)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            }
        }
    }

    private func applyOrientation(_ connection: AVCaptureConnection, mirror: Bool) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if mirror, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    /// Sets the device to the best MultiCam-compatible format for `quality`
    /// and `fps`, then locks the frame duration so the recording runs at a
    /// constant frame rate. Resolution wins over frame rate when the hardware
    /// can't do both (e.g. 4K60 dual-cam on older models).
    @discardableResult
    private func applyBestFormat(to device: AVCaptureDevice, quality: VideoQuality, fps: FrameRate) -> (widthOK: Bool, fpsOK: Bool) {
        func width(_ format: AVCaptureDevice.Format) -> Int32 {
            CMVideoFormatDescriptionGetDimensions(format.formatDescription).width
        }
        func supportsFPS(_ format: AVCaptureDevice.Format) -> Bool {
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(fps.rawValue) }
        }

        let multiCamFormats = device.formats.filter { $0.isMultiCamSupported }
        guard !multiCamFormats.isEmpty else { return (false, false) }

        let target = quality.formatWidth
        let chosen = multiCamFormats.last { width($0) == target && supportsFPS($0) }
            ?? multiCamFormats.last { width($0) == target }
            ?? multiCamFormats.filter { width($0) <= target && supportsFPS($0) }.max { width($0) < width($1) }
            ?? multiCamFormats.filter { width($0) <= target }.max { width($0) < width($1) }
            ?? multiCamFormats.min { width($0) < width($1) }

        guard let chosen else { return (false, false) }

        let maxSupported = chosen.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        let appliedFPS = min(Double(fps.rawValue), maxSupported)
        let duration = CMTime(value: 1, timescale: CMTimeScale(appliedFPS.rounded()))

        do {
            try device.lockForConfiguration()
            device.activeFormat = chosen
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            report(LocalizationManager.shared.t(.errFormatFailed, device.localizedName, error.localizedDescription))
            return (false, false)
        }

        return (width(chosen) >= target, appliedFPS >= Double(fps.rawValue))
    }

    private func device(for id: String?, fallback position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Session control

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - Recording

    func swapCameras() {
        DispatchQueue.main.async { self.isSwapped.toggle() }
    }

    func setQuality(_ quality: VideoQuality) {
        DispatchQueue.main.async {
            guard self.quality != quality, !self.isRecording else { return }
            self.quality = quality
            self.configure(backID: self.backCameraID, frontID: self.frontCameraID)
        }
    }

    func setFrameRate(_ frameRate: FrameRate) {
        DispatchQueue.main.async {
            guard self.frameRate != frameRate, !self.isRecording else { return }
            self.frameRate = frameRate
            self.configure(backID: self.backCameraID, frontID: self.frontCameraID)
        }
    }

    // MARK: - Back zoom / lens switching

    /// Builds the zoom presets from the back lenses that can pair with `frontID`.
    private func buildZoomPresets(frontID: String, currentBackID: String) -> ([ZoomPreset], ZoomPreset?) {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: multiCamDeviceTypes,
            mediaType: .video,
            position: .back
        )
        let backs = discovery.devices
        func pairable(_ id: String) -> Bool { areMultiCamCompatible(id, frontID) }

        var presets: [ZoomPreset] = []
        if let ultraWide = backs.first(where: { $0.deviceType == .builtInUltraWideCamera }), pairable(ultraWide.uniqueID) {
            presets.append(ZoomPreset(kind: .ultraWide, deviceID: ultraWide.uniqueID, zoomFactor: 1))
        }
        if let wide = backs.first(where: { $0.deviceType == .builtInWideAngleCamera }), pairable(wide.uniqueID) {
            presets.append(ZoomPreset(kind: .wide1x, deviceID: wide.uniqueID, zoomFactor: 1))
            presets.append(ZoomPreset(kind: .wide2x, deviceID: wide.uniqueID, zoomFactor: 2))
        }
        if let tele = backs.first(where: { $0.deviceType == .builtInTelephotoCamera }), pairable(tele.uniqueID) {
            presets.append(ZoomPreset(kind: .tele, deviceID: tele.uniqueID, zoomFactor: 1))
        }

        let active = presets.first { $0.deviceID == currentBackID && $0.zoomFactor == 1 } ?? presets.first { $0.deviceID == currentBackID }
        return (presets, active)
    }

    func selectBackZoom(_ preset: ZoomPreset) {
        sessionQueue.async {
            // Allowed during recording, matching the system camera: same-lens
            // zoom is a plain factor change, and cross-lens switches briefly
            // pause the session (a short gap in the recorded frames) but never
            // corrupt or stop the active recording.

            // Same physical lens → just adjust digital zoom, no reconfiguration.
            // Ramped so the transition glides like the system camera instead
            // of snapping.
            if self.backInput?.device.uniqueID == preset.deviceID {
                self.setZoomFactor(preset.zoomFactor, on: self.backInput?.device, animated: true)
                DispatchQueue.main.async {
                    self.activeZoom = preset
                    self.currentZoomFactor = preset.zoomFactor
                }
                return
            }

            guard let device = AVCaptureDevice(uniqueID: preset.deviceID) else { return }

            self.session.beginConfiguration()
            if let connection = self.backPreviewLayer.connection { self.session.removeConnection(connection) }
            if let connection = self.backDataConnection { self.session.removeConnection(connection) }
            if self.session.outputs.contains(self.backVideoOutput) { self.session.removeOutput(self.backVideoOutput) }
            if let input = self.backInput { self.session.removeInput(input) }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.report(LocalizationManager.shared.t(.errLensSwitchFailedGeneric))
                    return
                }
                self.session.addInputWithNoConnections(input)
                self.backInput = input
                self.applyBestFormat(to: device, quality: self.quality, fps: self.frameRate)
                self.backDataConnection = try self.connectCamera(
                    input: input, device: device, previewLayer: self.backPreviewLayer,
                    output: self.backVideoOutput, mirror: device.position == .front
                )
                self.session.commitConfiguration()

                self.setZoomFactor(preset.zoomFactor, on: device)
                self.applyMacroFocusIfNeeded(to: device)
                self.rebuildAfterBackSwap(backDevice: device)
                if let frontDevice = self.frontInput?.device {
                    self.beginWarmup(backDevice: device, frontDevice: frontDevice)
                }

                let torchAvailable = device.hasTorch && device.isTorchAvailable
                DispatchQueue.main.async {
                    self.backCameraID = device.uniqueID
                    self.activeZoom = preset
                    self.currentZoomFactor = preset.zoomFactor
                    self.isTorchAvailable = torchAvailable
                    self.torchMode = .off
                }
            } catch {
                self.session.commitConfiguration()
                self.report(LocalizationManager.shared.t(.errLensSwitchFailed, error.localizedDescription))
            }
        }
    }

    private func setZoomFactor(_ factor: CGFloat, on device: AVCaptureDevice?, animated: Bool = false) {
        guard let device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: clamped, withRate: 8)
            } else {
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
        } catch {
            report(LocalizationManager.shared.t(.errZoomFailed, error.localizedDescription))
        }
    }

    // MARK: - Pinch zoom

    /// Zoom factor at the moment the pinch began; pinch scale multiplies this.
    private var pinchStartZoom: CGFloat = 1

    /// Digital-zoom ceiling for pinch, mirroring the system camera's cap
    /// rather than exposing the sensor's absurd maximum (often 100×+).
    private let pinchMaxZoom: CGFloat = 10

    func beginPinchZoom() {
        sessionQueue.async {
            self.pinchStartZoom = self.backInput?.device.videoZoomFactor ?? 1
        }
    }

    func updatePinchZoom(scale: CGFloat) {
        sessionQueue.async {
            guard let device = self.backInput?.device else { return }
            let target = self.pinchStartZoom * scale
            let clamped = max(device.minAvailableVideoZoomFactor,
                              min(target, min(device.maxAvailableVideoZoomFactor, self.pinchMaxZoom)))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                return
            }

            let deviceID = device.uniqueID
            DispatchQueue.main.async {
                self.currentZoomFactor = clamped
                // Highlight a preset only when the factor lands on it exactly.
                self.activeZoom = self.zoomPresets.first {
                    $0.deviceID == deviceID && abs($0.zoomFactor - clamped) < 0.05
                }
            }
        }
    }

    /// iOS doesn't expose the stock Camera app's automatic macro lens-switch for
    /// custom MultiCam sessions (that behavior lives inside the virtual
    /// "Dual Wide Camera" device, which MultiCam can't use). As a practical
    /// stand-in, biasing the ultra-wide lens's focus to near subjects whenever
    /// it's selected gets close-up shots to focus reliably without a separate
    /// macro control.
    private func applyMacroFocusIfNeeded(to device: AVCaptureDevice) {
        guard device.isAutoFocusRangeRestrictionSupported else { return }
        do {
            try device.lockForConfiguration()
            device.autoFocusRangeRestriction = device.deviceType == .builtInUltraWideCamera ? .near : .none
            device.unlockForConfiguration()
        } catch {
            report(LocalizationManager.shared.t(.errFocusRangeFailed, error.localizedDescription))
        }
    }

    // MARK: - Torch

    /// Cycles 关(.off) → 自动(.auto) → 常亮(.on) → 关, matching the system camera.
    func cycleTorch() {
        sessionQueue.async {
            guard let device = self.backInput?.device, device.hasTorch, device.isTorchAvailable else { return }

            let next: AVCaptureDevice.TorchMode
            switch device.torchMode {
            case .off: next = .auto
            case .auto: next = .on
            case .on: next = .off
            @unknown default: next = .off
            }

            do {
                try device.lockForConfiguration()
                if device.isTorchModeSupported(next) {
                    device.torchMode = next
                } else {
                    // Some lenses skip .auto — fall straight through to .on.
                    device.torchMode = device.isTorchModeSupported(.on) ? .on : .off
                }
                device.unlockForConfiguration()
                let applied = device.torchMode
                DispatchQueue.main.async { self.torchMode = applied }
            } catch {
                self.report(LocalizationManager.shared.t(.errTorchFailed, error.localizedDescription))
            }
        }
    }

    // MARK: - Timer (delayed recording)

    private var countdownTimer: Timer?
    /// The action to run when a countdown reaches zero — starting a recording
    /// or arming a photo capture, whichever triggered it.
    private var pendingCountdownAction: (() -> Void)?

    /// Cycles 关 → 3s → 10s → 关.
    func cycleRecordDelay() {
        let options = [0, 3, 10]
        let index = options.firstIndex(of: recordDelaySeconds) ?? 0
        recordDelaySeconds = options[(index + 1) % options.count]
    }

    private func beginCountdown(action: @escaping () -> Void) {
        countdownRemaining = recordDelaySeconds
        pendingCountdownAction = action
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, let remaining = self.countdownRemaining else {
                timer.invalidate()
                return
            }
            let next = remaining - 1
            if next <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.countdownRemaining = nil
                let action = self.pendingCountdownAction
                self.pendingCountdownAction = nil
                action?()
            } else {
                self.countdownRemaining = next
            }
        }
    }

    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownRemaining = nil
        pendingCountdownAction = nil
    }

    // MARK: - Focus & exposure

    /// Sets the focus/exposure point for the given lens. `devicePoint` is in
    /// the 0...1 device coordinate space produced by
    /// `AVCaptureVideoPreviewLayer.captureDevicePointConverted(fromLayerPoint:)`.
    func focusAndExpose(at devicePoint: CGPoint, isBack: Bool) {
        sessionQueue.async {
            guard let device = isBack ? self.backInput?.device : self.frontInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    if device.isFocusModeSupported(.autoFocus) { device.focusMode = .autoFocus }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    if device.isExposureModeSupported(.autoExpose) { device.exposureMode = .autoExpose }
                }
                device.unlockForConfiguration()
            } catch {
                self.report(LocalizationManager.shared.t(.errFocusFailed, error.localizedDescription))
            }
        }
    }

    /// Valid exposure target bias range for the given lens (read-only, safe off-queue).
    func exposureBiasRange(isBack: Bool) -> ClosedRange<Float> {
        guard let device = isBack ? backInput?.device : frontInput?.device,
              device.minExposureTargetBias < device.maxExposureTargetBias else {
            return -2...2
        }
        return device.minExposureTargetBias...device.maxExposureTargetBias
    }

    func setExposureBias(_ bias: Float, isBack: Bool) {
        sessionQueue.async {
            guard let device = isBack ? self.backInput?.device : self.frontInput?.device else { return }
            let clamped = max(device.minExposureTargetBias, min(bias, device.maxExposureTargetBias))
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                self.report(LocalizationManager.shared.t(.errExposureFailed, error.localizedDescription))
            }
        }
    }

    /// After swapping the back input, rebuild rotation tracking and the
    /// synchronizer so both stay attached to the live outputs.
    private func rebuildAfterBackSwap(backDevice: AVCaptureDevice) {
        if let frontDevice = frontInput?.device {
            setupRotationTracking(backDevice: backDevice, frontDevice: frontDevice)
        }
        synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [backVideoOutput, frontVideoOutput, audioOutput])
        synchronizer?.setDelegate(self, queue: dataQueue)
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else if countdownRemaining != nil {
            cancelCountdown()
        } else if recordDelaySeconds > 0 {
            beginCountdown { self.startRecording() }
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        let mode = self.mode
        let quality = self.quality
        let codec = VideoCodec.stored
        let fps = self.frameRate.rawValue
        let dualOrientation = self.dualOrientation && mode.producesComposite
        // Lock the orientation for the whole clip using the preview's current,
        // already-stabilized angle (see applyPreviewAngle) rather than asking the
        // coordinator fresh — that avoids latching a bad angle if the phone
        // happens to be flat at the exact moment record is pressed.
        let captureAngle = backPreviewLayer.connection?.videoRotationAngle ?? 90
        let portrait = Int(captureAngle.rounded()) % 180 == 90

        sessionQueue.async {
            for connection in [self.backDataConnection, self.frontDataConnection].compactMap({ $0 }) {
                if connection.isVideoRotationAngleSupported(captureAngle) {
                    connection.videoRotationAngle = captureAngle
                }
            }

            self.dataQueue.async {
                do {
                    _ = try self.recorder.start(mode: mode, portrait: portrait, quality: quality, dualOrientation: dualOrientation, codec: codec, fps: fps)
                    DispatchQueue.main.async {
                        self.recordingStart = Date()
                        self.isRecording = true
                        self.recordingDuration = 0
                        self.startDurationTimer()
                    }
                } catch {
                    self.report(LocalizationManager.shared.t(.errRecordStartFailed, error.localizedDescription))
                }
            }
        }
    }

    private func stopRecording() {
        dataQueue.async {
            self.recorder.stop { output in
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.stopDurationTimer()
                    self.lastCaptureURL = output.urls.first
                    self.lastCaptureIsVideo = true
                    self.lastCaptureThumbnail = nil
                    self.finishVideoCaptures(urls: output.urls)
                }
            }
        }
    }

    /// Thumbnail extraction and Photos hand-off for finished clips, strictly
    /// in that order: the Photos save deletes the sandbox file on success, so
    /// the thumbnail frame must be read out before the save is even started.
    private func finishVideoCaptures(urls: [URL]) {
        Task.detached(priority: .utility) {
            if let first = urls.first {
                let asset = AVURLAsset(url: first)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    let image = UIImage(cgImage: cgImage)
                    await MainActor.run { self.lastCaptureThumbnail = image }
                }
            }

            for url in urls {
                self.saveToPhotoLibrary(url: url, isVideo: true)
            }
        }
    }

    /// Moves a finished capture into the user's Photos library, then deletes
    /// the sandbox original — Photos owns the copy, so keeping ours would
    /// silently double every capture's disk usage forever. The sandbox file
    /// survives only when the save fails (no permission / error): it is then
    /// the user's only copy, reachable via the Files app, and gets reclaimed
    /// by `cleanupStaleCaptures` after a week.
    private func saveToPhotoLibrary(url: URL, isVideo: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                self.report(LocalizationManager.shared.t(.errPhotoLibraryPermission))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if isVideo {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } else {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }) { success, error in
                if success {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    let loc = LocalizationManager.shared
                    self.report(loc.t(.errPhotoLibrarySaveFailed, error?.localizedDescription ?? loc.t(.errUnknown)))
                }
            }
        }
    }

    /// Launch-time sweep: deletes sandbox captures older than 7 days. Recent
    /// files are deliberately kept — a file only lingers here when its Photos
    /// save failed, so the user gets a week to rescue it via the Files app
    /// before the space is reclaimed.
    private func cleanupStaleCaptures() {
        Task.detached(priority: .background) {
            let fm = FileManager.default
            let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            guard let files = try? fm.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }

            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            for file in files where file.lastPathComponent.hasPrefix("DualCamera-") {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if modified < cutoff {
                    try? fm.removeItem(at: file)
                }
            }
        }
    }

    // MARK: - Photo capture

    /// Arms a still-photo capture that fires on the next synchronized frame
    /// pair. In split/pip modes this saves one composed JPEG; in 双录 mode it
    /// saves two independent JPEGs, mirroring how video recording splits output.
    func capturePhoto() {
        if countdownRemaining != nil {
            cancelCountdown()
        } else if recordDelaySeconds > 0 {
            beginCountdown { self.armPhotoCapture() }
        } else {
            armPhotoCapture()
        }
    }

    private func armPhotoCapture() {
        dataQueue.async { self.photoCaptureArmed = true }
    }

    private func savePhoto(back: CMSampleBuffer, front: CMSampleBuffer?) {
        guard let backPixels = CMSampleBufferGetImageBuffer(back) else { return }
        let frontPixels = front.flatMap { CMSampleBufferGetImageBuffer($0) }

        let mode = self.mode
        let angle = backPreviewLayer.connection?.videoRotationAngle ?? 90
        let portrait = Int(angle.rounded()) % 180 == 90
        let size = quality.renderSize(portrait: portrait)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = Self.photoTimestamp()

        var savedURLs: [URL] = []
        var thumbnailImage: UIImage?

        func write(_ ciImage: CIImage, to url: URL) {
            guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent),
                  let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.92) else { return }
            do {
                try data.write(to: url, options: .atomic)
                savedURLs.append(url)
                if thumbnailImage == nil { thumbnailImage = UIImage(cgImage: cgImage) }
            } catch {
                report(LocalizationManager.shared.t(.errPhotoSaveFailed, error.localizedDescription))
            }
        }

        switch mode {
        case .split, .pip:
            let composed = DualFrameCompositor.compose(back: backPixels, front: frontPixels, mode: mode, size: size, portrait: portrait)
            write(composed, to: directory.appendingPathComponent("DualCamera-\(stamp).jpg"))
        case .dualFile:
            write(CIImage(cvPixelBuffer: backPixels), to: directory.appendingPathComponent("DualCamera-\(stamp)-back.jpg"))
            if let frontPixels {
                write(CIImage(cvPixelBuffer: frontPixels), to: directory.appendingPathComponent("DualCamera-\(stamp)-front.jpg"))
            }
        }

        guard let firstURL = savedURLs.first else {
            report(LocalizationManager.shared.t(.errPhotoSaveFailedGeneric))
            return
        }

        for url in savedURLs {
            saveToPhotoLibrary(url: url, isVideo: false)
        }

        DispatchQueue.main.async {
            self.lastCaptureURL = firstURL
            self.lastCaptureIsVideo = false
            self.lastCaptureThumbnail = thumbnailImage
        }
    }

    private static func photoTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStart else { return }
            self.recordingDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStart = nil
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { self.lastError = message }
    }
}

// MARK: - Synchronized capture

extension DualCameraController: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        let backRaw = (synchronizedDataCollection.synchronizedData(for: backVideoOutput) as? AVCaptureSynchronizedSampleBufferData)
            .flatMap { $0.sampleBufferWasDropped ? nil : $0.sampleBuffer }
        let frontRaw = (synchronizedDataCollection.synchronizedData(for: frontVideoOutput) as? AVCaptureSynchronizedSampleBufferData)
            .flatMap { $0.sampleBufferWasDropped ? nil : $0.sampleBuffer }
        let audio = (synchronizedDataCollection.synchronizedData(for: audioOutput) as? AVCaptureSynchronizedSampleBufferData)
            .flatMap { $0.sampleBufferWasDropped ? nil : $0.sampleBuffer }

        let back = isSwapped ? frontRaw : backRaw
        let front = isSwapped ? backRaw : frontRaw

        if photoCaptureArmed, let back {
            photoCaptureArmed = false
            savePhoto(back: back, front: front)
        }

        guard recorder.isRecording else { return }
        recorder.append(back: back, front: front, audio: audio)
    }
}
