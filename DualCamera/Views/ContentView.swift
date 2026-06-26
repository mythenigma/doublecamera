import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var sessionController = CameraSessionController()
    @State private var report: CameraCapabilityReport?
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var selectedDeviceID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    permissionPanel
                    summaryPanel
                    liveCapturePanel
                    devicePanel
                    multiCamPanel
                    captureResultsPanel
                    diagnosticsPanel
                }
                .padding()
            }
            .navigationTitle("DualCamera")
            .toolbar {
                Button("Rescan") {
                    refresh()
                }
            }
            .task {
                refresh()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Camera Capability Console")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Internal hardware probe: devices, formats, frame rates, HDR, and MultiCam sets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionPanel: some View {
        panel("Permission") {
            HStack {
                statusDot(isOK: authorizationStatus == .authorized)
                Text(cameraPermissionText)
                    .font(.callout)

                Spacer()

                if authorizationStatus == .notDetermined {
                    Button("Request") {
                        requestCameraAccess()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var summaryPanel: some View {
        panel("Runtime Summary") {
            if let report {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Generated")
                        Text(report.generatedAt.formatted(date: .omitted, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("Devices")
                        Text("\(report.devices.count)")
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("MultiCam")
                        Text(report.isMultiCamSupported ? "supported" : "not supported")
                            .foregroundStyle(report.isMultiCamSupported ? .green : .orange)
                    }
                    GridRow {
                        Text("Sets")
                        Text("\(report.supportedMultiCamSets.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout.monospaced())
            } else {
                Text("No scan yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var devicePanel: some View {
        panel("Devices") {
            if let devices = report?.devices, !devices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
            } else {
                Text(authorizationStatus == .authorized ? "No camera devices discovered." : "Authorize camera access to scan hardware.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var liveCapturePanel: some View {
        panel("Live Capture") {
            VStack(alignment: .leading, spacing: 12) {
                PreviewView(session: sessionController.session)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(selectedDeviceLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    Button("Start Preview") {
                        startSelectedCamera()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedDeviceID == nil || authorizationStatus != .authorized)

                    Button("Stop") {
                        sessionController.stop()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!sessionController.isRunning)

                    Button("Photo") {
                        sessionController.capturePhoto()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!sessionController.isRunning)

                    Button(sessionController.isRecording ? "Stop Rec" : "Record") {
                        if sessionController.isRecording {
                            sessionController.stopRecording()
                        } else {
                            sessionController.startRecording()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!sessionController.isRunning)
                }

                HStack {
                    statusDot(isOK: sessionController.isRunning)
                    Text(sessionController.isRunning ? "session running" : "session stopped")
                    Spacer()
                    Text(sessionController.isRecording ? "recording" : "idle")
                        .foregroundStyle(sessionController.isRecording ? .red : .secondary)
                }
                .font(.caption.monospaced())
            }
        }
    }

    private var multiCamPanel: some View {
        panel("MultiCam Sets") {
            if let report, report.supportedMultiCamSets.isEmpty {
                Text(report.isMultiCamSupported ? "No supported sets reported by this discovery session." : "AVCaptureMultiCamSession is not supported on this device/configuration.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array((report?.supportedMultiCamSets ?? []).enumerated()), id: \.offset) { index, set in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(set.joined(separator: "\n"))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var captureResultsPanel: some View {
        panel("Capture Results") {
            if sessionController.captures.isEmpty {
                Text(sessionController.lastOutputPath ?? "No photos or videos captured yet.")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sessionController.captures) { capture in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(capture.kind.uppercased())  \(capture.date.formatted(date: .omitted, time: .standard))")
                                .font(.caption.monospaced())
                            Text(capture.outputPath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        panel("Diagnostics") {
            let diagnostics = sessionController.diagnostics + (report?.diagnostics ?? [])
            if diagnostics.isEmpty {
                Text("No diagnostics.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(diagnostics) { entry in
                        Text("[\(entry.level)] \(entry.message)")
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: CameraDeviceSummary) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(device.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("\(device.formats.count) formats")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(device.formats.prefix(20)) { format in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(format.dimensions)  \(format.mediaSubType)  HDR: \(format.isVideoHDRSupported ? "yes" : "no")")
                            .font(.caption.monospaced())
                        Text(format.frameRateRanges.joined(separator: ", "))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if device.formats.count > 20 {
                    Text("+ \(device.formats.count - 20) more formats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.localizedName)
                        .font(.headline)
                    Spacer()
                    Text(device.position)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(device.deviceType)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                HStack {
                    Button(selectedDeviceID == device.id ? "Selected" : "Select") {
                        selectedDeviceID = device.id
                    }
                    .buttonStyle(.bordered)

                    Button("Start") {
                        selectedDeviceID = device.id
                        sessionController.startSingleCamera(deviceID: device.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authorizationStatus != .authorized)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statusDot(isOK: Bool) -> some View {
        Circle()
            .fill(isOK ? .green : .orange)
            .frame(width: 10, height: 10)
    }

    private var cameraPermissionText: String {
        switch authorizationStatus {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { _ in
            Task { @MainActor in
                refresh()
            }
        }
    }

    @MainActor
    private func refresh() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorizationStatus == .authorized else {
            report = CameraCapabilityReport(
                generatedAt: Date(),
                isMultiCamSupported: AVCaptureMultiCamSession.isMultiCamSupported,
                devices: [],
                supportedMultiCamSets: [],
                diagnostics: [
                    DiagnosticEntry(
                        id: UUID(),
                        date: Date(),
                        level: "warning",
                        message: "Camera access is \(cameraPermissionText)."
                    )
                ],
                captures: []
            )
            return
        }

        report = CameraCapabilityScanner().scan()
        if selectedDeviceID == nil {
            selectedDeviceID = report?.devices.first?.id
        }
    }

    private var selectedDeviceLabel: String {
        guard let selectedDeviceID else {
            return "No camera selected."
        }

        let device = report?.devices.first { $0.id == selectedDeviceID }
        return "Selected: \(device?.localizedName ?? "Unknown")  \(selectedDeviceID)"
    }

    private func startSelectedCamera() {
        guard let selectedDeviceID else {
            return
        }

        sessionController.startSingleCamera(deviceID: selectedDeviceID)
    }
}

#Preview {
    ContentView()
}
