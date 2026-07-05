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

/// Live position/size of the picture-in-picture window, shared between the
/// preview layout and the recording/photo compositor so what the user drags
/// on screen is exactly what lands in the file (WYSIWYG).
struct PipLayout: Equatable {
    /// Window center, normalized 0...1 in UI coordinates (y grows downward).
    var center = CGPoint(x: 0.80, y: 0.20)
    /// Size multiplier on the base window width; double-tap toggles it.
    var scale: CGFloat = 1

    static let enlargedScale: CGFloat = 1.55
    /// Base window width as a fraction of the canvas width.
    static let baseWidthFraction: CGFloat = 0.32

    /// The window rect inside a canvas of `size`, clamped fully on-canvas.
    /// The same math runs on the preview bounds and the export canvas.
    func rect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let width = size.width * Self.baseWidthFraction * scale
        let height = width * (size.height / size.width)
        let margin: CGFloat = size.width * 0.02

        var x = center.x * size.width - width / 2
        var y = center.y * size.height - height / 2
        x = min(max(x, margin), size.width - width - margin)
        y = min(max(y, margin), size.height - height - margin)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    mutating func toggleScale() {
        scale = scale == 1 ? Self.enlargedScale : 1
    }
}

/// A back-camera zoom preset shown in the zoom bar. Each maps to a physical
/// lens plus a digital zoom factor applied on top of it.
struct ZoomPreset: Identifiable, Equatable {
    enum Kind: Equatable {
        case ultraWide, wide1x, wide2x, tele
    }

    let kind: Kind
    let deviceID: String
    let zoomFactor: CGFloat

    /// Computed at render time (not stored at configure time) so the
    /// localized tele label updates the moment the app language changes.
    var label: String {
        switch kind {
        case .ultraWide: return ".5×"
        case .wide1x: return "1×"
        case .wide2x: return "2×"
        case .tele: return LocalizationManager.shared.t(.lensTele)
        }
    }

    var id: String { "\(deviceID)-\(zoomFactor)" }
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
