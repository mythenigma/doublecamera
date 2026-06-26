import Foundation

enum CapabilityReportExporter {
    static func encode(report: CameraCapabilityReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    static func write(report: CameraCapabilityReport, to url: URL) throws {
        let data = try encode(report: report)
        try data.write(to: url, options: .atomic)
    }
}
