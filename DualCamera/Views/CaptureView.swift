import AVFoundation
import SwiftUI
import UIKit

/// The consumer-facing dual-camera recording screen.
struct CaptureView: View {
    @StateObject private var controller = DualCameraController()
    @ObservedObject private var loc = LocalizationManager.shared

    @State private var cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var didConfigureOnce = false

    @State private var focusIndicator: FocusIndicator?
    @State private var exposureDragValue: Float = 0
    @State private var focusDismissTask: Task<Void, Never>?
    @State private var showMoreControls = false

    private struct FocusIndicator: Identifiable {
        let id = UUID()
        var point: CGPoint
        var isBack: Bool
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    landscapeContent
                } else {
                    portraitContent
                }
            }

            if showMoreControls {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { showMoreControls = false } }

                VStack {
                    HStack {
                        Spacer()
                        moreControlsPanel
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .padding(.top, 64)
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }

            if showPicker {
                Color.black.opacity(0.4).ignoresSafeArea()
                CameraPickerView(
                    cameras: controller.availableCameras,
                    initialPrimary: controller.backCameraID,
                    initialSecondary: controller.frontCameraID,
                    arePairable: { controller.areMultiCamCompatible($0, $1) },
                    onConfirm: { primary, secondary in
                        // Assign by actual physical position, not tap order:
                        // whichever pick is the front (selfie) lens always
                        // becomes frontID, regardless of which button was
                        // tapped first in the grid.
                        let picks = [primary, secondary]
                        let frontPick = picks.first { id in
                            controller.availableCameras.first { $0.id == id }?.position == .front
                        }
                        let backPick = picks.first { $0 != frontPick }

                        controller.configure(backID: backPick ?? primary, frontID: frontPick ?? secondary)
                        didConfigureOnce = true
                        withAnimation { showPicker = false }
                    },
                    onClose: { withAnimation { showPicker = false } }
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .task { await bootstrap() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Orientation layouts

    private var portraitContent: some View {
        VStack(spacing: 0) {
            topBar
            previewArea
            bottomControls
        }
    }

    private var landscapeContent: some View {
        HStack(spacing: 0) {
            previewArea
            controlColumn
                .frame(width: 188)
        }
    }

    /// Right-hand control rail used in landscape.
    private var controlColumn: some View {
        VStack(spacing: 14) {
            HStack {
                gearButton
                Spacer()
                topBarTrailingCluster
            }
            timerText
            Spacer()
            modeColumn
            recordButton
            HStack(spacing: 18) {
                thumbnail
                photoButton
                gridButton
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            gearButton
            Spacer()
            timerText
            Spacer()
            topBarTrailingCluster
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var gearButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 18))
                .foregroundStyle(.white)
        }
    }

    private var timerText: some View {
        Text(timeString(controller.recordingDuration))
            .font(.title3.weight(.semibold).monospacedDigit())
            .foregroundStyle(controller.isRecording ? .red : .white)
    }

    /// Always-visible icon cluster: torch, timer, and the "more" overflow toggle.
    private var topBarTrailingCluster: some View {
        HStack(spacing: 0) {
            torchButton
            timerButton
            moreButton
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var moreButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showMoreControls.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
        }
    }

    /// Overflow panel — quality, frame rate, and 竖横同拍, styled like the
    /// system camera's icon-over-label control grid.
    private var moreControlsPanel: some View {
        HStack(spacing: 16) {
            moreControlItem(
                topText: controller.quality.label,
                label: loc.t(.qualityLabel),
                active: controller.quality == .uhd4k,
                warning: controller.quality == .uhd4k && !controller.fourKAvailable
            ) {
                controller.setQuality(controller.quality == .hd ? .uhd4k : .hd)
            }
            moreControlItem(topText: "60", label: loc.t(.fpsLabel), active: false, warning: false, action: {})
            moreToggleItem(
                icon: "rectangle.on.rectangle",
                label: loc.t(.dualOrientationLabel),
                active: controller.dualOrientation,
                disabled: controller.isRecording || controller.mode == .dualFile
            ) {
                controller.dualOrientation.toggle()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func moreControlItem(
        topText: String,
        label: String,
        active: Bool,
        warning: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(active ? Color.yellow : Color.white.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Text(topText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(active ? .black : .white)
                    if warning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.black)
                            .padding(3)
                            .background(Color.yellow, in: Circle())
                            .offset(x: 15, y: -15)
                    }
                }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func moreToggleItem(
        icon: String,
        label: String,
        active: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(active ? Color.yellow : Color.white.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(active ? .black : .white)
                }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    // MARK: - Preview

    private var previewArea: some View {
        ZStack {
            if cameraAuthorized && controller.isMultiCamSupported {
                DualPreviewView(
                    controller: controller,
                    mode: controller.mode,
                    swapped: controller.isSwapped,
                    onFocusTap: { viewPoint, devicePoint, isBack in
                        handleFocusTap(viewPoint: viewPoint, devicePoint: devicePoint, isBack: isBack)
                    },
                    onSwap: { controller.swapCameras() }
                )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topLeading) { outputChip }
                    .overlay { if controller.mode == .dualFile { dualFileMarkers } }
                    .overlay { if let focusIndicator { focusReticle(focusIndicator) } }
                    .overlay(alignment: .bottom) {
                        if controller.zoomPresets.count > 1 { zoomBar.padding(.bottom, 14) }
                    }
                    .overlay(alignment: .bottomLeading) { swapButton }
                    .overlay(alignment: .top) { if controller.isWarmingUp { warmupIndicator } }
                    .overlay { if let remaining = controller.countdownRemaining { countdownOverlay(remaining) } }
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(white: 0.12))
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: cameraAuthorized ? "exclamationmark.triangle" : "camera.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.6))
                            Text(cameraAuthorized
                                 ? loc.t(.errorNoMultiCam)
                                 : loc.t(.errorNeedPermission))
                                .foregroundStyle(.white.opacity(0.8))
                            if !cameraAuthorized {
                                Button(loc.t(.buttonGrantPermission)) { Task { await requestAccess() } }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                            }
                        }
                    }
            }

            if let error = controller.lastError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 12)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    /// Chip that states whether the active mode writes one composed file or two.
    private var outputChip: some View {
        HStack(spacing: 5) {
            Image(systemName: controller.mode.producesComposite ? "doc" : "doc.on.doc")
                .font(.caption2)
            Text(controller.mode.outputDescription)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(12)
    }

    /// In 双录 mode, label each half so it reads as two independent files.
    private var dualFileMarkers: some View {
        GeometryReader { geo in
            let tag1 = fileTag(loc.t(.fileTag1)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            let tag2 = fileTag(loc.t(.fileTag2)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if geo.size.width > geo.size.height {
                HStack(spacing: 0) { tag1; tag2 }
            } else {
                VStack(spacing: 0) { tag1; tag2 }
            }
        }
        .padding(.top, 48)
        .padding(.leading, 12)
        .allowsHitTesting(false)
    }

    private func fileTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.85), in: Capsule())
    }

    /// Back-camera zoom/lens switcher (.5× / 1× / 2× / 长焦).
    private var zoomBar: some View {
        HStack(spacing: 6) {
            ForEach(controller.zoomPresets) { preset in
                let active = controller.activeZoom == preset
                Button { controller.selectBackZoom(preset) } label: {
                    Text(preset.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(active ? .yellow : .white.opacity(0.85))
                        .frame(minWidth: active ? 40 : 28, minHeight: 28)
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Yellow focus/exposure box shown at the tapped point, with a vertical
    /// sun-icon slider for dragging exposure bias up/down.
    private func focusReticle(_ indicator: FocusIndicator) -> some View {
        let range = controller.exposureBiasRange(isBack: indicator.isBack)
        let span = max(range.upperBound - range.lowerBound, 0.01)
        let trackHeight: CGFloat = 72
        let knobOffset = CGFloat(-exposureDragValue / span) * trackHeight

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 72, height: 72)

            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 3, height: trackHeight)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)
                    .offset(y: knobOffset)
            }
            .frame(width: 36, height: trackHeight + 24)
            .offset(x: 54)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let normalized = Float(-value.translation.height / trackHeight)
                        let bias = max(range.lowerBound, min(range.upperBound, normalized * span))
                        exposureDragValue = bias
                        controller.setExposureBias(bias, isBack: indicator.isBack)
                        scheduleFocusDismiss()
                    }
            )
        }
        .position(indicator.point)
        .transition(.opacity)
    }

    /// Shown briefly while both lenses' auto-exposure settles after start/switch.
    private var warmupIndicator: some View {
        Text(loc.t(.warmupIndicator))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
            .transition(.opacity)
    }

    private func countdownOverlay(_ remaining: Int) -> some View {
        ZStack {
            Color.black.opacity(0.25)
            Text("\(remaining)")
                .font(.system(size: 100, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .id(remaining)
                .transition(.scale.combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    /// 手电筒 — cycles 关 / 自动 / 常亮, used as recording fill light.
    private var torchButton: some View {
        Button { controller.cycleTorch() } label: {
            Image(systemName: torchIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(controller.torchMode == .off ? .white : .yellow)
                .frame(width: 30, height: 30)
        }
        .disabled(!controller.isTorchAvailable)
        .opacity(controller.isTorchAvailable ? 1 : 0.3)
    }

    private var torchIcon: String {
        switch controller.torchMode {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }

    /// 计时器 — cycles 关 / 3s / 10s delayed recording start.
    private var timerButton: some View {
        Button { controller.cycleRecordDelay() } label: {
            ZStack {
                Image(systemName: "timer")
                    .font(.system(size: 14, weight: .medium))
                if controller.recordDelaySeconds > 0 {
                    Text("\(controller.recordDelaySeconds)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(2.5)
                        .background(Color.yellow, in: Circle())
                        .offset(x: 11, y: -9)
                }
            }
            .foregroundStyle(controller.recordDelaySeconds > 0 ? .yellow : .white)
            .frame(width: 30, height: 30)
        }
        .disabled(controller.isRecording || controller.countdownRemaining != nil)
    }

    private var swapButton: some View {
        Button { controller.swapCameras() } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(16)
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        VStack(spacing: 10) {
            modeBar

            HStack {
                thumbnail
                Spacer()
                photoButton
                Spacer()
                recordButton
                Spacer()
                gridButton
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var modeBar: some View {
        HStack(spacing: 24) {
            ForEach(CaptureMode.allCases) { modeButton($0) }
        }
    }

    private var modeColumn: some View {
        VStack(spacing: 14) {
            ForEach(CaptureMode.allCases) { modeButton($0) }
        }
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { controller.mode = mode }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.body)
                Text(mode.title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(controller.mode == mode ? .red : .white.opacity(0.7))
            .frame(width: 64)
        }
        .disabled(controller.isRecording)
    }

    private var recordButton: some View {
        Button {
            controller.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: controller.isRecording ? 8 : 34, style: .continuous)
                    .fill(Color.red)
                    .frame(
                        width: controller.isRecording ? 34 : 64,
                        height: controller.isRecording ? 34 : 64
                    )
            }
        }
        .disabled(!controller.isRunning || (controller.isWarmingUp && !controller.isRecording))
        .opacity(controller.isRunning ? 1 : 0.4)
    }

    private var thumbnail: some View {
        Button {
            openPhotosApp()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(white: 0.2))
                if let image = controller.lastCaptureThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(.white.opacity(0.7))
                }
                if controller.lastCaptureIsVideo && controller.lastCaptureURL != nil {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.5), lineWidth: 1))
        }
        .disabled(controller.lastCaptureURL == nil)
    }

    /// Shutter button — captures a still (composed in split/pip, two
    /// independent frames in 双录) without interrupting video recording state.
    private var photoButton: some View {
        Button { controller.capturePhoto() } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())
        }
        .disabled(!controller.isRunning || controller.isRecording || controller.isWarmingUp)
        .opacity(controller.isRunning && !controller.isRecording && !controller.isWarmingUp ? 1 : 0.4)
    }

    private var gridButton: some View {
        Button {
            controller.discoverCameras()
            withAnimation { showPicker = true }
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(controller.isRecording)
    }

    /// Jumps straight to the system Photos app, same as the stock Camera
    /// app's thumbnail button — no in-app preview screen.
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Focus / exposure

    private func handleFocusTap(viewPoint: CGPoint, devicePoint: CGPoint, isBack: Bool) {
        controller.focusAndExpose(at: devicePoint, isBack: isBack)
        exposureDragValue = 0
        withAnimation(.easeOut(duration: 0.15)) {
            focusIndicator = FocusIndicator(point: viewPoint, isBack: isBack)
        }
        scheduleFocusDismiss()
    }

    private func scheduleFocusDismiss() {
        focusDismissTask?.cancel()
        focusDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { focusIndicator = nil }
        }
    }

    // MARK: - Lifecycle

    private func bootstrap() async {
        await requestAccess()
        guard cameraAuthorized else { return }
        controller.discoverCameras()
        // Give discovery a moment to populate before presenting the picker.
        try? await Task.sleep(nanoseconds: 250_000_000)
        if !didConfigureOnce {
            withAnimation { showPicker = true }
        }
    }

    private func requestAccess() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

#Preview {
    CaptureView()
}
