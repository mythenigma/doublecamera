import AVFoundation
import Foundation

final class CameraSessionController: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()

    @Published private(set) var activeDeviceID: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var diagnostics: [DiagnosticEntry] = []
    @Published private(set) var captures: [CaptureResult] = []
    @Published private(set) var lastOutputPath: String?

    private let sessionQueue = DispatchQueue(label: "CameraSessionController.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    func startSingleCamera(deviceID: String) {
        sessionQueue.async {
            guard let device = AVCaptureDevice(uniqueID: deviceID) else {
                self.log(level: "error", message: "Device not found: \(deviceID)")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }

                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.log(level: "error", message: "Cannot add input for \(device.localizedName).")
                    return
                }
                self.session.addInput(input)

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                } else {
                    self.log(level: "warning", message: "Photo output is unavailable for this session.")
                }

                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                } else {
                    self.log(level: "warning", message: "Movie output is unavailable for this session.")
                }

                self.session.commitConfiguration()
                self.session.startRunning()

                DispatchQueue.main.async {
                    self.activeDeviceID = deviceID
                    self.isRunning = self.session.isRunning
                }
                self.log(level: "info", message: "Started preview: \(device.localizedName)")
            } catch {
                self.log(level: "error", message: "Failed to start camera: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            DispatchQueue.main.async {
                self.isRunning = false
                self.isRecording = false
                self.activeDeviceID = nil
            }
            self.log(level: "info", message: "Stopped session.")
        }
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.session.isRunning else {
                self.log(level: "error", message: "Cannot capture photo because session is not running.")
                return
            }

            guard self.session.outputs.contains(self.photoOutput) else {
                self.log(level: "error", message: "Photo output is not attached to the active session.")
                return
            }

            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
            self.log(level: "info", message: "Photo capture requested.")
        }
    }

    func startRecording() {
        sessionQueue.async {
            guard self.session.isRunning else {
                self.log(level: "error", message: "Cannot record because session is not running.")
                return
            }

            guard self.session.outputs.contains(self.movieOutput) else {
                self.log(level: "error", message: "Movie output is not attached to the active session.")
                return
            }

            guard !self.movieOutput.isRecording else {
                self.log(level: "warning", message: "Recording is already active.")
                return
            }

            let url = Self.documentsURL().appendingPathComponent("DualCamera-\(Self.timestamp()).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)

            DispatchQueue.main.async {
                self.isRecording = true
                self.lastOutputPath = url.path
            }
            self.log(level: "info", message: "Started recording: \(url.lastPathComponent)")
        }
    }

    func stopRecording() {
        sessionQueue.async {
            guard self.movieOutput.isRecording else {
                self.log(level: "warning", message: "No active recording to stop.")
                return
            }

            self.movieOutput.stopRecording()
            self.log(level: "info", message: "Stopping recording.")
        }
    }

    private func recordCapture(kind: String, outputURL: URL, metadata: [String: String] = [:]) {
        let result = CaptureResult(
            id: UUID(),
            date: Date(),
            kind: kind,
            outputPath: outputURL.path,
            metadata: metadata
        )

        DispatchQueue.main.async {
            self.captures.insert(result, at: 0)
            self.lastOutputPath = outputURL.path
        }
    }

    private func log(level: String, message: String) {
        let entry = DiagnosticEntry(id: UUID(), date: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.diagnostics.insert(entry, at: 0)
        }
    }

    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            log(level: "error", message: "Photo capture failed: \(error.localizedDescription)")
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            log(level: "error", message: "Photo capture produced no JPEG data.")
            return
        }

        let url = Self.documentsURL().appendingPathComponent("DualCamera-\(Self.timestamp()).jpg")

        do {
            try data.write(to: url, options: .atomic)
            recordCapture(kind: "photo", outputURL: url, metadata: ["bytes": "\(data.count)"])
            log(level: "info", message: "Photo saved: \(url.lastPathComponent)")
        } catch {
            log(level: "error", message: "Photo save failed: \(error.localizedDescription)")
        }
    }
}

extension CameraSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isRecording = false
        }

        if let error {
            log(level: "error", message: "Recording failed: \(error.localizedDescription)")
            return
        }

        recordCapture(kind: "video", outputURL: outputFileURL)
        log(level: "info", message: "Recording saved: \(outputFileURL.lastPathComponent)")
    }
}
