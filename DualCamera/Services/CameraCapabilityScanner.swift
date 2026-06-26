import AVFoundation
import CoreMedia
import Foundation

final class CameraCapabilityScanner {
    func scan() -> CameraCapabilityReport {
        let devices = discoverDevices()
        let multiCamSets = supportedMultiCamSets()
        let diagnostics = [
            DiagnosticEntry(
                id: UUID(),
                date: Date(),
                level: "info",
                message: "Scanned \(devices.count) video capture devices and \(multiCamSets.count) multi-camera sets."
            )
        ]

        return CameraCapabilityReport(
            generatedAt: Date(),
            isMultiCamSupported: AVCaptureMultiCamSession.isMultiCamSupported,
            devices: devices,
            supportedMultiCamSets: multiCamSets,
            diagnostics: diagnostics,
            captures: []
        )
    }

    private func discoverDevices() -> [CameraDeviceSummary] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: discoveryDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices
            .sorted { left, right in
                "\(left.position.rawValue)-\(left.localizedName)" < "\(right.position.rawValue)-\(right.localizedName)"
            }
            .map(makeDeviceSummary)
    }

    private var discoveryDeviceTypes: [AVCaptureDevice.DeviceType] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera
        ]

        if #available(iOS 15.4, *) {
            types.append(.builtInLiDARDepthCamera)
        }

        return types
    }

    private func makeDeviceSummary(_ device: AVCaptureDevice) -> CameraDeviceSummary {
        CameraDeviceSummary(
            id: device.uniqueID,
            localizedName: device.localizedName,
            position: describe(position: device.position),
            deviceType: device.deviceType.rawValue,
            formats: device.formats.enumerated().map { index, format in
                makeFormatSummary(format, index: index)
            }
        )
    }

    private func makeFormatSummary(_ format: AVCaptureDevice.Format, index: Int) -> CameraFormatSummary {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let frameRateRanges = format.videoSupportedFrameRateRanges.map { range in
            String(format: "%.0f-%.0f fps", range.minFrameRate, range.maxFrameRate)
        }

        return CameraFormatSummary(
            id: "\(index)-\(dimensions.width)x\(dimensions.height)-\(fourCC(mediaSubType))",
            dimensions: "\(dimensions.width)x\(dimensions.height)",
            mediaSubType: fourCC(mediaSubType),
            frameRateRanges: frameRateRanges,
            isVideoHDRSupported: format.isVideoHDRSupported
        )
    }

    private func supportedMultiCamSets() -> [[String]] {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            return []
        }

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: discoveryDeviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        return discovery.supportedMultiCamDeviceSets.map { deviceSet in
            deviceSet
                .map(\.uniqueID)
                .sorted()
        }
        .sorted { $0.joined(separator: "|") < $1.joined(separator: "|") }
    }

    private func describe(position: AVCaptureDevice.Position) -> String {
        switch position {
        case .back:
            return "back"
        case .front:
            return "front"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }

    private func fourCC(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]

        if let string = String(bytes: bytes, encoding: .ascii), string.allSatisfy({ $0.isASCII && !$0.isWhitespace }) {
            return string
        }

        return "\(value)"
    }
}
