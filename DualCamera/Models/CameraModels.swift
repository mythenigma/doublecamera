import Foundation

struct CameraCapabilityReport: Codable, Equatable {
    var generatedAt: Date
    var isMultiCamSupported: Bool
    var devices: [CameraDeviceSummary]
    var supportedMultiCamSets: [[String]]
    var diagnostics: [DiagnosticEntry]
    var captures: [CaptureResult]
}

struct CameraDeviceSummary: Codable, Equatable, Identifiable {
    var id: String
    var localizedName: String
    var position: String
    var deviceType: String
    var formats: [CameraFormatSummary]
}

struct CameraFormatSummary: Codable, Equatable, Identifiable {
    var id: String
    var dimensions: String
    var mediaSubType: String
    var frameRateRanges: [String]
    var isVideoHDRSupported: Bool
}

struct DiagnosticEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var level: String
    var message: String
}

struct CaptureResult: Codable, Equatable, Identifiable {
    var id: UUID
    var date: Date
    var kind: String
    var outputPath: String
    var metadata: [String: String]
}
