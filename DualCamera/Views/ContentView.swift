import AVFoundation
import SwiftUI

struct ContentView: View {
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
                    devicePanel
                    multiCamPanel
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

    private var diagnosticsPanel: some View {
        panel("Diagnostics") {
            let diagnostics = report?.diagnostics ?? []
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
    }
}

#Preview {
    ContentView()
}
