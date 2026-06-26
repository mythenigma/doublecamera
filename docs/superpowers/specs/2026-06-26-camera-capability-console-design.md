# Camera Capability Console Design

## Goal

Build an internal iPhone camera engineering console that exposes the device's camera capabilities and proves them with real capture. The first version is for local development and hardware exploration, not a polished consumer camera app.

The app should answer four questions on a real iPhone:

1. Which cameras and capture formats are available on this device?
2. Which camera combinations can run at the same time?
3. Can the selected camera or camera pair preview, take photos, and record video?
4. What errors, pressure states, and thermal constraints appear during operation?

## Scope

Version 1 includes:

- Camera permission flow using standard iOS privacy prompts.
- Runtime discovery of available video capture devices.
- Runtime discovery of multi-camera support.
- A dense SwiftUI control console for camera devices, formats, combinations, session state, and logs.
- Single-camera preview.
- Multi-camera preview for supported pairs.
- Photo capture.
- Video recording of the current composed preview.
- JSON export of the current device capability report and test results.

Version 1 excludes:

- App Store polish.
- Social sharing.
- Editing, filters, beauty effects, or templates.
- Livestreaming.
- Separate synchronized raw recordings for each camera feed.
- Cross-device comparison UI beyond JSON export.

## Product Shape

The first screen is the console itself. It should not have a landing page.

The UI is split into four working areas:

- Device panel: lists discovered cameras, device types, positions, unique IDs, active formats, and supported format summaries.
- Combination panel: lists supported multi-camera sets and lets the developer choose one or two cameras to start.
- Preview panel: shows live single-camera or dual-camera preview. Dual-camera mode uses a composed layout such as side-by-side or picture-in-picture.
- Diagnostics panel: shows session state, system pressure, thermal state, capture permissions, recent errors, and capture output paths.

The UI may use AVFoundation terminology directly because the first audience is the developer.

## Architecture

Use SwiftUI for the console shell and AVFoundation for capture.

Core units:

- `CameraCapabilityScanner`
  - Discovers available `AVCaptureDevice` instances.
  - Reads formats, frame-rate ranges, dimensions, media subtype, HDR-related flags where available, stabilization support where available, and position/device type.
  - Reads whether `AVCaptureMultiCamSession.isMultiCamSupported` is true.
  - Produces a serializable capability report.

- `CameraSessionController`
  - Owns the active capture session.
  - Configures either a single-camera session or a multi-camera session.
  - Handles start, stop, reconfiguration, interruptions, runtime errors, pressure state, and thermal updates.
  - Publishes state to SwiftUI on the main actor.

- `PreviewComposer`
  - Receives one or two video streams.
  - Presents live preview.
  - Provides the composed video frames used for recording.
  - Starts with a simple side-by-side or picture-in-picture layout.

- `PhotoCaptureController`
  - Captures still images in single-camera mode with `AVCapturePhotoOutput` where supported.
  - In multi-camera mode, attempts photo capture for the selected primary camera when supported.
  - Falls back to a video-frame snapshot when photo output is unavailable in the active configuration.
  - Saves output locally and records metadata.

- `VideoRecordingController`
  - Records the current composed preview with `AVAssetWriter`.
  - Starts with one composed `.mov` output rather than separate per-camera files.
  - Records capture metadata in the session log and JSON report.

- `CapabilityReportExporter`
  - Writes JSON containing device discovery data, supported combinations, selected formats, capture attempts, errors, and output file paths.

## Capture Strategy

Single-camera mode can use a normal `AVCaptureSession`.

Dual-camera mode uses `AVCaptureMultiCamSession` only when supported. The app must never assume a specific iPhone model or fixed camera pair. It discovers what the connected device supports at runtime and degrades gracefully when a combination fails.

For recording, version 1 records the composed preview rather than each raw stream separately. This keeps the first implementation focused on proving camera scheduling and capture output. Separate synchronized raw stream recording can be added later after preview, pressure handling, and composition are stable.

## Error Handling

Every failed operation should produce a visible diagnostic entry:

- Permission denied or restricted.
- Multi-camera unsupported.
- Device unavailable.
- Unsupported camera pair.
- Session configuration failure.
- Runtime interruption.
- System pressure or thermal pressure changes.
- Photo capture failure.
- Recording start, append, or finish failure.

The app should keep running when possible and let the developer stop, re-scan, or try another camera pair.

## Data Flow

1. App launches and requests camera and microphone permissions when needed.
2. Scanner builds the device capability report.
3. Console renders devices, formats, and supported combinations.
4. Developer selects mode and cameras.
5. Session controller configures preview inputs and outputs.
6. Preview composer displays live frames.
7. Photo and recording controllers capture outputs using the active session.
8. Diagnostics and exporter record results.

## Testing Plan

Use a real iPhone for all camera behavior. Simulator tests are useful only for basic SwiftUI rendering and data-model tests.

Verification targets:

- App builds for iOS.
- App installs on connected iPhone.
- Permission prompts appear with clear usage descriptions.
- Scanner returns at least one video camera on device.
- Capability report exports valid JSON.
- Single-camera preview starts and stops.
- Supported dual-camera preview starts and stops when available.
- Unsupported pairs fail with a visible error instead of crashing.
- Photo capture writes an output file or explicit failure log.
- Recording writes a playable `.mov` file or explicit failure log.

## Initial Implementation Order

1. Create the iOS SwiftUI project.
2. Add permissions and basic app shell.
3. Implement camera discovery and JSON report export.
4. Implement single-camera preview.
5. Implement multi-camera session setup and dual preview.
6. Implement photo capture.
7. Implement composed video recording.
8. Add diagnostics, pressure, thermal, and interruption logs.
9. Run on connected iPhone and fix device-specific failures.
