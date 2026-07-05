import AVFoundation
import SwiftUI
import UIKit

/// Hosts the controller's two preview layers and arranges them for the
/// active `CaptureMode`. Also owns tap-to-focus/expose, double-tap, pinch,
/// and PiP-drag gestures, since they all need the live layer frames.
struct DualPreviewView: UIViewRepresentable {
    let controller: DualCameraController
    let mode: CaptureMode
    let swapped: Bool
    let pipLayout: PipLayout

    /// Called with the tapped point in view coordinates (for drawing a
    /// reticle), the equivalent 0...1 device point (for AVFoundation focus
    /// APIs), and whether the back (vs front) lens was tapped.
    var onFocusTap: ((_ viewPoint: CGPoint, _ devicePoint: CGPoint, _ isBack: Bool) -> Void)?
    var onSwap: (() -> Void)?
    var onPinchBegan: (() -> Void)?
    var onPinchChanged: ((_ scale: CGFloat) -> Void)?
    var onPipLayoutChanged: ((PipLayout) -> Void)?
    var onPipScaleToggle: (() -> Void)?

    func makeUIView(context: Context) -> DualPreviewHostView {
        let view = DualPreviewHostView()
        view.attach(back: controller.backPreviewLayer, front: controller.frontPreviewLayer)
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: DualPreviewHostView, context: Context) {
        apply(to: uiView)
    }

    private func apply(to view: DualPreviewHostView) {
        view.mode = mode
        view.swapped = swapped
        // While the user's finger owns the window, the gesture is the source
        // of truth — pushing published state back mid-drag would fight it.
        if !view.isDraggingPip {
            view.pipLayout = pipLayout
        }
        view.onFocusTap = onFocusTap
        view.onSwap = onSwap
        view.onPinchBegan = onPinchBegan
        view.onPinchChanged = onPinchChanged
        view.onPipLayoutChanged = onPipLayoutChanged
        view.onPipScaleToggle = onPipScaleToggle
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

    var pipLayout = PipLayout() {
        didSet {
            guard oldValue != pipLayout else { return }
            setNeedsLayout()
        }
    }

    private(set) var isDraggingPip = false

    var onFocusTap: ((_ viewPoint: CGPoint, _ devicePoint: CGPoint, _ isBack: Bool) -> Void)?
    var onSwap: (() -> Void)?
    var onPinchBegan: (() -> Void)?
    var onPinchChanged: ((_ scale: CGFloat) -> Void)?
    var onPipLayoutChanged: ((PipLayout) -> Void)?
    var onPipScaleToggle: (() -> Void)?

    private weak var backLayer: AVCaptureVideoPreviewLayer?
    private weak var frontLayer: AVCaptureVideoPreviewLayer?
    /// Whichever layer is currently drawn on top (only set in PiP, where the
    /// two layers overlap); used to hit-test taps in the right order.
    private weak var topOverlayLayer: AVCaptureVideoPreviewLayer?

    /// Normalized window center at the moment a drag began.
    private var dragStartCenter: CGPoint = .zero

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

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }

    private func pointIsOnPipWindow(_ point: CGPoint) -> Bool {
        mode == .pip && topOverlayLayer?.frame.contains(point) == true
    }

    /// Double-tap on the floating window resizes it; anywhere else swaps
    /// the two feeds (the pre-existing behavior).
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if pointIsOnPipWindow(gesture.location(in: self)) {
            onPipScaleToggle?()
        } else {
            onSwap?()
        }
    }

    /// Dragging the floating window moves it, YouTube/FaceTime-style. Pans
    /// starting anywhere else are ignored.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard pointIsOnPipWindow(gesture.location(in: self)) else { return }
            isDraggingPip = true
            dragStartCenter = pipLayout.center
        case .changed:
            guard isDraggingPip, bounds.width > 0, bounds.height > 0 else { return }
            let translation = gesture.translation(in: self)
            var layout = pipLayout
            layout.center = CGPoint(
                x: dragStartCenter.x + translation.x / bounds.width,
                y: dragStartCenter.y + translation.y / bounds.height
            )
            pipLayout = layout
            onPipLayoutChanged?(layout)
        case .ended, .cancelled, .failed:
            guard isDraggingPip else { return }
            isDraggingPip = false
            // Persist the clamped-on-canvas center so the export compositor
            // (which clamps the same way) and future layouts agree exactly.
            let rect = pipLayout.rect(in: bounds.size)
            var layout = pipLayout
            layout.center = CGPoint(
                x: rect.midX / bounds.width,
                y: rect.midY / bounds.height
            )
            pipLayout = layout
            onPipLayoutChanged?(layout)
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            onPinchBegan?()
        case .changed:
            onPinchChanged?(gesture.scale)
        default:
            break
        }
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

            // Same PipLayout math the recording compositor uses — the window
            // records exactly where the user sees it.
            secondaryLayer.frame = pipLayout.rect(in: bounds.size)
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
