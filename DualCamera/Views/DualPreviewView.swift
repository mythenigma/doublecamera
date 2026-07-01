import AVFoundation
import SwiftUI
import UIKit

/// Hosts the controller's two preview layers and arranges them for the
/// active `CaptureMode`. Also owns tap-to-focus/expose and double-tap-to-swap
/// gestures, since both need to reason about the live layer frames.
struct DualPreviewView: UIViewRepresentable {
    let controller: DualCameraController
    let mode: CaptureMode
    let swapped: Bool

    /// Called with the tapped point in view coordinates (for drawing a
    /// reticle), the equivalent 0...1 device point (for AVFoundation focus
    /// APIs), and whether the back (vs front) lens was tapped.
    var onFocusTap: ((_ viewPoint: CGPoint, _ devicePoint: CGPoint, _ isBack: Bool) -> Void)?
    var onSwap: (() -> Void)?

    func makeUIView(context: Context) -> DualPreviewHostView {
        let view = DualPreviewHostView()
        view.attach(back: controller.backPreviewLayer, front: controller.frontPreviewLayer)
        view.mode = mode
        view.swapped = swapped
        view.onFocusTap = onFocusTap
        view.onSwap = onSwap
        return view
    }

    func updateUIView(_ uiView: DualPreviewHostView, context: Context) {
        uiView.mode = mode
        uiView.swapped = swapped
        uiView.onFocusTap = onFocusTap
        uiView.onSwap = onSwap
    }
}

final class DualPreviewHostView: UIView {
    var mode: CaptureMode = .pip {
        didSet {
            guard oldValue != mode else { return }
            setNeedsLayout()
        }
    }

    var swapped: Bool = false {
        didSet {
            guard oldValue != swapped else { return }
            setNeedsLayout()
        }
    }

    var onFocusTap: ((_ viewPoint: CGPoint, _ devicePoint: CGPoint, _ isBack: Bool) -> Void)?
    var onSwap: (() -> Void)?

    private weak var backLayer: AVCaptureVideoPreviewLayer?
    private weak var frontLayer: AVCaptureVideoPreviewLayer?
    /// Whichever layer is currently drawn on top (only set in PiP, where the
    /// two layers overlap); used to hit-test taps in the right order.
    private weak var topOverlayLayer: AVCaptureVideoPreviewLayer?

    func attach(back: AVCaptureVideoPreviewLayer, front: AVCaptureVideoPreviewLayer) {
        backLayer = back
        frontLayer = front
        layer.addSublayer(back)
        layer.addSublayer(front)
        front.cornerRadius = 18
        front.masksToBounds = true
        backgroundColor = .black
        setupGestures()
    }

    private func setupGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    @objc private func handleDoubleTap() {
        onSwap?()
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)

        let tappedLayer: AVCaptureVideoPreviewLayer?
        if let topOverlayLayer, topOverlayLayer.frame.contains(point) {
            tappedLayer = topOverlayLayer
        } else if let backLayer, backLayer.frame.contains(point) {
            tappedLayer = backLayer
        } else if let frontLayer, frontLayer.frame.contains(point) {
            tappedLayer = frontLayer
        } else {
            tappedLayer = nil
        }

        guard let tappedLayer else { return }
        let localPoint = tappedLayer.convert(point, from: layer)
        let devicePoint = tappedLayer.captureDevicePointConverted(fromLayerPoint: localPoint)
        onFocusTap?(point, devicePoint, tappedLayer === backLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let backLayer, let frontLayer else { return }
        let bounds = self.bounds

        // Resolve which physical layer plays the main vs the secondary role.
        let mainLayer = swapped ? frontLayer : backLayer
        let secondaryLayer = swapped ? backLayer : frontLayer

        switch mode {
        case .pip:
            mainLayer.cornerRadius = 0
            mainLayer.frame = bounds

            let pipWidth = bounds.width * 0.34
            let pipHeight = pipWidth * (bounds.height / max(bounds.width, 1))
            let inset: CGFloat = 16
            secondaryLayer.frame = CGRect(
                x: bounds.maxX - pipWidth - inset,
                y: bounds.minY + inset,
                width: pipWidth,
                height: pipHeight
            )
            secondaryLayer.cornerRadius = 18
            // Keep the overlay on top.
            secondaryLayer.zPosition = 1
            mainLayer.zPosition = 0
            topOverlayLayer = secondaryLayer

        case .split, .dualFile:
            mainLayer.cornerRadius = 0
            secondaryLayer.cornerRadius = 0
            mainLayer.zPosition = 0
            secondaryLayer.zPosition = 0
            topOverlayLayer = nil
            if bounds.width > bounds.height {
                // Landscape: split left / right.
                let half = bounds.width / 2
                mainLayer.frame = CGRect(x: 0, y: 0, width: half, height: bounds.height)
                secondaryLayer.frame = CGRect(x: half, y: 0, width: half, height: bounds.height)
            } else {
                // Portrait: split top / bottom.
                let half = bounds.height / 2
                mainLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: half)
                secondaryLayer.frame = CGRect(x: 0, y: half, width: bounds.width, height: half)
            }
        }
    }
}
