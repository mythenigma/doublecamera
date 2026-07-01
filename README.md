# DualCamera

An iOS app that previews, records, and photographs two cameras at once — front and back, or two rear lenses — using `AVCaptureMultiCamSession`. Built with SwiftUI and AVFoundation for iOS 17+.

## Features

- **Three capture modes**
  - **Split** — both feeds stacked, composed into one file (top/bottom in portrait, left/right in landscape)
  - **PIP** — one feed full-screen with the other in a floating overlay, one file
  - **Dual Rec** — each camera records to its own independent file
- **Any two compatible lenses** — pick from ultra-wide / wide / tele / front (selfie), the app only offers pairs the hardware can actually run simultaneously via `AVCaptureMultiCamSession.supportedMultiCamDeviceSets`
- **Back-lens zoom bar** — `.5×` / `1×` / `2×` / tele, switchable even while recording
- **Photo capture** — composed still in Split/PIP, two independent stills in Dual Rec
- **HD / 4K quality toggle** — auto-falls-back with an on-screen warning if a lens can't hit the requested resolution in MultiCam mode
- **Portrait + Landscape capture** — optionally writes each composite recording twice, once in portrait and once in landscape, in one take
- **Torch** — off / auto / on, cycling like the system camera
- **Self-timer** — 3s / 10s delayed start, works for both video and photo
- **Tap to focus/expose** — per-lens focus + exposure point, with a draggable exposure-bias slider
- **Front/back swap** — double-tap the preview or use the swap button to flip which feed is "main"
- **Saves to Photos** — captures land in the system Photos library (plus a local copy for the in-app thumbnail); tapping the thumbnail jumps straight to the Photos app
- **Auto-exposure warm-up guard** — blocks record/photo for a moment after a lens starts/switches so the exposure-ramp-up isn't captured in the clip
- **Manual language picker** — English, Deutsch, 中文, 日本語, Français, chosen in Settings; the app does **not** follow the system locale automatically and defaults to English
- **Built-in dev console** — a separate camera-capability scanner (device/format/frame-rate discovery, JSON export) reachable from Settings, useful when bringing up support for a new device

## Requirements

- A physical iPhone with at least two cameras that support `AVCaptureMultiCamSession` (the iOS Simulator cannot run MultiCam sessions)
- iOS 17.0+
- Xcode 16+, Swift 6

## Getting started

```bash
git clone https://github.com/mythenigma/doublecamera.git
cd doublecamera
open DualCamera.xcodeproj
```

In Xcode, select the `DualCamera` scheme, set your own signing team under the target's Signing & Capabilities tab, and run on a connected device.

## Project structure

```
DualCamera/
  App/            App entry point, Info.plist, app icon
  Views/          SwiftUI screens (capture UI, camera picker, settings, dev console)
  Services/       AVFoundation session/recording engine
  Models/         Capture mode / zoom / camera option types
  Localization/   Manual 5-language string table (no system-locale detection)
DualCameraTests/  Unit tests for the models and capability report exporter
docs/             Design notes for the original capability-console version
```

Core pieces, if you're digging into the AVFoundation side:

- `DualCameraController` — owns the `AVCaptureMultiCamSession`, both preview layers, lens switching, zoom, torch, focus/exposure, and the exposure warm-up guard
- `DualStreamRecorder` — `AVAssetWriter`-based recorder; one composed output for Split/PIP (optionally two, for Portrait + Landscape capture), two independent outputs for Dual Rec
- `DualFrameCompositor` — the actual split/PIP drawing math, shared between the recorder and still-photo capture so both look identical
- `DualPreviewView` — hosts the two `AVCaptureVideoPreviewLayer`s, lays them out per mode/orientation, and owns the tap-to-focus / double-tap-to-swap gestures

## Known limitations

- Switching between physical lenses mid-recording briefly pauses the session (a short gap in the recorded frames on both channels) — same-lens digital zoom (e.g. 1×→2×) has no such gap
- "Macro" is approximated: selecting the ultra-wide lens restricts autofocus to near subjects. iOS doesn't expose the stock Camera app's automatic macro lens-switch to custom MultiCam sessions — that behavior lives inside a virtual multi-lens device that `AVCaptureMultiCamSession` can't use
- 4K is requested per lens and may silently fall back to a lower resolution (flagged with a warning icon) if the hardware can't sustain 4K on both lenses simultaneously
- The `ContentView` dev console (camera capability scanner) is intentionally left in English only — it's a debugging tool, not part of the localized consumer UI

## License

No license has been chosen yet — add a `LICENSE` file before treating this as open source under a specific license (MIT is a common default for permissive projects like this).
