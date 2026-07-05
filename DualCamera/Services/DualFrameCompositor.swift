import CoreImage
import CoreVideo

/// Shared split / picture-in-picture composition math, used by both the
/// video recorder and still-photo capture so the two stay visually identical.
enum DualFrameCompositor {
    static func compose(back: CVPixelBuffer, front: CVPixelBuffer?, mode: CaptureMode, size: CGSize, portrait: Bool, pip: PipLayout = PipLayout()) -> CIImage {
        composeImages(
            back: CIImage(cvPixelBuffer: back),
            front: front.map { CIImage(cvPixelBuffer: $0) },
            mode: mode,
            size: size,
            portrait: portrait,
            pip: pip
        )
    }

    /// CIImage-level entry used by still-photo capture, where the inputs come
    /// from `AVCapturePhoto` data rather than video pixel buffers.
    static func composeImages(back backImage: CIImage, front frontImage: CIImage?, mode: CaptureMode, size: CGSize, portrait: Bool, pip: PipLayout = PipLayout()) -> CIImage {
        let canvas = CGRect(origin: .zero, size: size)
        var result = CIImage(color: .black).cropped(to: canvas)

        switch mode {
        case .pip:
            result = aspectFill(backImage, into: canvas).cropped(to: canvas).composited(over: result)
            if let frontImage {
                // PipLayout.rect works in UI coordinates (y down); CoreImage's
                // origin is bottom-left, so flip the vertical placement.
                let uiRect = pip.rect(in: size)
                let pipRect = CGRect(
                    x: uiRect.minX,
                    y: size.height - uiRect.maxY,
                    width: uiRect.width,
                    height: uiRect.height
                )
                let overlay = aspectFill(frontImage, into: pipRect)
                result = overlay.cropped(to: pipRect).composited(over: result)
            }

        case .split:
            let firstRect: CGRect
            let secondRect: CGRect
            if portrait {
                firstRect = CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
                secondRect = CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
            } else {
                firstRect = CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
                secondRect = CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
            }
            result = aspectFill(backImage, into: firstRect).cropped(to: firstRect).composited(over: result)
            if let frontImage {
                result = aspectFill(frontImage, into: secondRect).cropped(to: secondRect).composited(over: result)
            }

        case .dualFile:
            break
        }

        return result
    }

    /// Scales and translates `image` so it fills `rect` (aspect fill, centered).
    static func aspectFill(_ image: CIImage, into rect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scale = max(rect.width / extent.width, rect.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent

        let tx = rect.midX - scaledExtent.midX
        let ty = rect.midY - scaledExtent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
    }
}
