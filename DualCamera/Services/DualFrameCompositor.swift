import CoreImage
import CoreVideo

/// Shared split / picture-in-picture composition math, used by both the
/// video recorder and still-photo capture so the two stay visually identical.
enum DualFrameCompositor {
    static func compose(back: CVPixelBuffer, front: CVPixelBuffer?, mode: CaptureMode, size: CGSize, portrait: Bool) -> CIImage {
        let backImage = CIImage(cvPixelBuffer: back)
        let canvas = CGRect(origin: .zero, size: size)
        var result = CIImage(color: .black).cropped(to: canvas)

        switch mode {
        case .pip:
            result = aspectFill(backImage, into: canvas).cropped(to: canvas).composited(over: result)
            if let front {
                let inset = size.width * 0.033
                let pipWidth = size.width * 0.32
                let pipHeight = pipWidth * (size.height / size.width)
                let pipRect = CGRect(
                    x: size.width - pipWidth - inset,
                    y: size.height - pipHeight - inset,
                    width: pipWidth,
                    height: pipHeight
                )
                let frontImage = aspectFill(CIImage(cvPixelBuffer: front), into: pipRect)
                result = frontImage.cropped(to: pipRect).composited(over: result)
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
            if let front {
                result = aspectFill(CIImage(cvPixelBuffer: front), into: secondRect).cropped(to: secondRect).composited(over: result)
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
