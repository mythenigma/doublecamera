import XCTest
@testable import DualCamera

final class CameraModelsTests: XCTestCase {
    func testCapabilityReportEncodesDeviceAndCaptureDetails() throws {
        let report = CameraCapabilityReport(
            generatedAt: Date(timeIntervalSince1970: 1_782_453_600),
            isMultiCamSupported: true,
            devices: [
                CameraDeviceSummary(
                    id: "wide-back",
                    localizedName: "Back Wide Camera",
                    position: "back",
                    deviceType: "builtInWideAngleCamera",
                    formats: [
                        CameraFormatSummary(
                            id: "1920x1080-420f",
                            dimensions: "1920x1080",
                            mediaSubType: "420f",
                            frameRateRanges: ["24.0-60.0"],
                            isVideoHDRSupported: true
                        )
                    ]
                )
            ],
            supportedMultiCamSets: [["wide-back", "front-true-depth"]],
            diagnostics: [
                DiagnosticEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    date: Date(timeIntervalSince1970: 1_782_453_601),
                    level: "info",
                    message: "Scan completed"
                )
            ],
            captures: [
                CaptureResult(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    date: Date(timeIntervalSince1970: 1_782_453_602),
                    kind: "photo",
                    outputPath: "/tmp/photo.jpg",
                    metadata: ["deviceID": "wide-back"]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let json = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder.iso8601.decode(CameraCapabilityReport.self, from: data)

        XCTAssertTrue(json.contains("Back Wide Camera"))
        XCTAssertTrue(json.contains("\"isMultiCamSupported\":true"))
        XCTAssertEqual(decoded.captures.first?.outputPath, "/tmp/photo.jpg")
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
