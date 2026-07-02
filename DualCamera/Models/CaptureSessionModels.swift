import AVFoundation
import Foundation

/// How the two camera feeds are composed for preview and recording.
enum CaptureMode: String, CaseIterable, Identifiable {
    /// 分割 — two feeds stacked, composed into a single file.
    case split
    /// 画中画 — primary feed full-screen with the secondary feed in an overlay, single file.
    case pip
    /// 双文件 — each camera records to its own independent file.
    case dualFile

    var id: String { rawValue }

    /// Localized label shown in the mode bar.
    var title: String {
        let loc = LocalizationManager.shared
        switch self {
        case .split: return loc.t(.modeSplit)
        case .pip: return loc.t(.modePip)
        case .dualFile: return loc.t(.modeDualFile)
        }
    }

    /// Short description of what this mode writes to disk.
    var outputDescription: String {
        let loc = LocalizationManager.shared
        return producesComposite ? loc.t(.outputComposite) : loc.t(.outputDualFile)
    }

    var systemImage: String {
        switch self {
        case .split: return "rectangle.split.1x2"
        case .pip: return "pip"
        case .dualFile: return "square.on.square"
        }
    }

    /// True when the two feeds are flattened into one composed output file.
    var producesComposite: Bool {
        self != .dualFile
    }
}

/// Recording resolution tier, surfaced by the top-bar quality badge.
enum VideoQuality: String, CaseIterable, Identifiable {
    case hd
    case uhd4k

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hd: return "HD"
        case .uhd4k: return "4K"
        }
    }

    /// Long edge of the encoded frame (portrait height / landscape width).
    var longEdge: CGFloat {
        switch self {
        case .hd: return 1920
        case .uhd4k: return 3840
        }
    }

    /// Short edge of the encoded frame (portrait width / landscape height).
    var shortEdge: CGFloat {
        switch self {
        case .hd: return 1080
        case .uhd4k: return 2160
        }
    }

    /// Sensor-format width (landscape) used when picking an `AVCaptureDevice.Format`.
    var formatWidth: Int32 { Int32(longEdge) }

    func renderSize(portrait: Bool) -> CGSize {
        portrait
            ? CGSize(width: shortEdge, height: longEdge)
            : CGSize(width: longEdge, height: shortEdge)
    }
}

/// Recording frame rate, surfaced next to the quality control.
enum FrameRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }

    var label: String { "\(rawValue)fps" }

    var frameDuration: CMTime { CMTime(value: 1, timescale: CMTimeScale(rawValue)) }
}

/// Video codec choice: HEVC produces ~40% smaller files at the same quality;
/// H.264 plays everywhere including old Windows/Android players.
enum VideoCodec: String, CaseIterable, Identifiable {
    case hevc
    case h264

    var id: String { rawValue }

    /// Persisted in UserDefaults under this key; read at recording start.
    static let storageKey = "VideoCodec"

    static var stored: VideoCodec {
        UserDefaults.standard.string(forKey: storageKey).flatMap(VideoCodec.init) ?? .hevc
    }

    var avCodec: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .h264: return .h264
        }
    }

    /// Rough perceptual bits-per-pixel for each codec, used to compute an
    /// explicit average bitrate from resolution × frame rate.
    var bitsPerPixel: Double {
        switch self {
        case .hevc: return 0.11
        case .h264: return 0.17
        }
    }

    /// Ceiling so 4K60 doesn't produce absurd file sizes.
    var maxBitrate: Int {
        switch self {
        case .hevc: return 45_000_000
        case .h264: return 60_000_000
        }
    }

    func averageBitrate(size: CGSize, fps: Int) -> Int {
        let pixelRate = Double(size.width * size.height) * Double(fps)
        return min(Int(pixelRate * bitsPerPixel), maxBitrate)
    }
}

/// A back-camera zoom preset shown in the zoom bar. Each maps to a physical
/// lens plus a digital zoom factor applied on top of it.
struct ZoomPreset: Identifiable, Equatable {
    let label: String
    let deviceID: String
    let zoomFactor: CGFloat

    var id: String { label }
}

/// A selectable camera lens presented in the picker grid.
struct CameraOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let position: AVCaptureDevice.Position
    let deviceType: AVCaptureDevice.DeviceType

    /// Human friendly lens name derived from device type and position.
    static func displayName(for device: AVCaptureDevice) -> String {
        let loc = LocalizationManager.shared
        switch device.deviceType {
        case .builtInUltraWideCamera:
            return loc.t(.lensUltraWide)
        case .builtInTelephotoCamera:
            return loc.t(.lensTele)
        case .builtInWideAngleCamera:
            return device.position == .front ? loc.t(.lensSelfie) : loc.t(.lensWide)
        default:
            return device.position == .front ? loc.t(.lensSelfie) : device.localizedName
        }
    }
}
