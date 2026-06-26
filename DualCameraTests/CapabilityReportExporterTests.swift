import XCTest
@testable import DualCamera

final class CapabilityReportExporterTests: XCTestCase {
    func testEncodeUsesPrettyPrintedSortedISO8601JSON() throws {
        let report = makeReport()

        let data = try CapabilityReportExporter.encode(report: report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\n"))
        XCTAssertTrue(json.contains("\"captures\""))
        XCTAssertTrue(json.contains("2026-06-26T06:00:00Z"))
        let capturesOffset = json.distance(from: json.startIndex, to: json.range(of: "\"captures\"")!.lowerBound)
        let devicesOffset = json.distance(from: json.startIndex, to: json.range(of: "\"devices\"")!.lowerBound)
        XCTAssertLessThan(capturesOffset, devicesOffset)
    }

    func testWriteCreatesReportFile() throws {
        let report = makeReport()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("report.json")

        try CapabilityReportExporter.write(report: report, to: url)

        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder.iso8601.decode(CameraCapabilityReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }

    private func makeReport() -> CameraCapabilityReport {
        CameraCapabilityReport(
            generatedAt: ISO8601DateFormatter().date(from: "2026-06-26T06:00:00Z")!,
            isMultiCamSupported: false,
            devices: [],
            supportedMultiCamSets: [],
            diagnostics: [],
            captures: [
                CaptureResult(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    date: ISO8601DateFormatter().date(from: "2026-06-26T06:00:01Z")!,
                    kind: "video",
                    outputPath: "/tmp/video.mov",
                    metadata: [:]
                )
            ]
        )
    }
}
