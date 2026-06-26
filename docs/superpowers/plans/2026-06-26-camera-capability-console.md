# Camera Capability Console Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a SwiftUI iOS app that scans iPhone camera capabilities, previews single or dual cameras, captures photos, records the composed preview, and exports JSON diagnostics.

**Architecture:** The app uses a small SwiftUI shell backed by focused AVFoundation controllers. Pure data models and export logic are covered by XCTest first; AVFoundation behavior is verified by build checks plus real-device manual tests because camera hardware cannot be exercised meaningfully in the simulator.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Photos, XCTest, Xcode 26.5.

---

## File Structure

- `DualCamera.xcodeproj/project.pbxproj`: Native Xcode project with app and unit test targets.
- `DualCamera/App/DualCameraApp.swift`: SwiftUI app entry point.
- `DualCamera/App/Info.plist`: Camera, microphone, and photo library usage descriptions.
- `DualCamera/Models/CameraModels.swift`: Codable capability, format, diagnostic, and capture result models.
- `DualCamera/Services/CapabilityReportExporter.swift`: JSON export helper.
- `DualCamera/Services/CameraCapabilityScanner.swift`: Runtime camera discovery.
- `DualCamera/Services/CameraSessionController.swift`: Single and multi-camera session ownership.
- `DualCamera/Services/PhotoCaptureController.swift`: Still photo capture and snapshot fallback hooks.
- `DualCamera/Services/VideoRecordingController.swift`: Composed preview recording with `AVAssetWriter`.
- `DualCamera/Views/ContentView.swift`: Four-panel console UI.
- `DualCamera/Views/PreviewView.swift`: UIKit-backed preview layer host.
- `DualCameraTests/CapabilityReportExporterTests.swift`: JSON export tests.
- `DualCameraTests/CameraModelsTests.swift`: Model encoding and summarization tests.

## Task 1: Create Buildable iOS Project

**Files:**
- Create: `DualCamera.xcodeproj/project.pbxproj`
- Create: `DualCamera/App/DualCameraApp.swift`
- Create: `DualCamera/App/Info.plist`
- Create: `DualCamera/Views/ContentView.swift`
- Create: `DualCameraTests/CameraModelsTests.swift`

- [ ] **Step 1: Create the minimal app and test target**

Create a SwiftUI iOS project named `DualCamera` with bundle identifier `com.local.dualcamera`. Include an app target and an XCTest target.

- [ ] **Step 2: Add privacy strings**

Add:

```xml
<key>NSCameraUsageDescription</key>
<string>This internal camera console needs camera access to inspect, preview, photograph, and record camera feeds.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This internal camera console may use microphone access when testing video recording.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This internal camera console saves captured photos and videos for inspection.</string>
```

- [ ] **Step 3: Verify the generated app builds**

Run:

```bash
xcodebuild -project DualCamera.xcodeproj -scheme DualCamera -destination 'generic/platform=iOS' build
```

Expected: build exits 0.

- [ ] **Step 4: Commit**

```bash
git add DualCamera.xcodeproj DualCamera DualCameraTests
git commit -m "Create iOS app project"
```

## Task 2: Add Codable Camera Models With Tests

**Files:**
- Create: `DualCamera/Models/CameraModels.swift`
- Create: `DualCameraTests/CameraModelsTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that encode a `CameraCapabilityReport` with one device, one format, one diagnostic entry, and one capture result. Assert the JSON contains the device name, multi-camera flag, and capture output path.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project DualCamera.xcodeproj -scheme DualCamera -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: tests fail because the model types do not exist yet.

- [ ] **Step 3: Implement models**

Define these Codable models:

```swift
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
```

- [ ] **Step 4: Run tests and verify pass**

Run the same `xcodebuild test` command. Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add DualCamera/Models/CameraModels.swift DualCameraTests/CameraModelsTests.swift
git commit -m "Add camera capability models"
```

## Task 3: Add JSON Exporter With Tests

**Files:**
- Create: `DualCamera/Services/CapabilityReportExporter.swift`
- Create: `DualCameraTests/CapabilityReportExporterTests.swift`

- [ ] **Step 1: Write failing exporter tests**

Test that `CapabilityReportExporter.encode(report:)` returns pretty-printed sorted-key JSON and that `write(report:to:)` creates a file.

- [ ] **Step 2: Verify red**

Run the simulator test command. Expected: exporter type is missing.

- [ ] **Step 3: Implement exporter**

Implement:

```swift
enum CapabilityReportExporter {
    static func encode(report: CameraCapabilityReport) throws -> Data
    static func write(report: CameraCapabilityReport, to url: URL) throws
}
```

Use `JSONEncoder` with `.prettyPrinted`, `.sortedKeys`, and `.iso8601`.

- [ ] **Step 4: Verify green and commit**

Run tests, then commit:

```bash
git add DualCamera/Services/CapabilityReportExporter.swift DualCameraTests/CapabilityReportExporterTests.swift
git commit -m "Add capability report exporter"
```

## Task 4: Implement Camera Discovery

**Files:**
- Create: `DualCamera/Services/CameraCapabilityScanner.swift`
- Modify: `DualCamera/Views/ContentView.swift`

- [ ] **Step 1: Add scanner interface**

Create `CameraCapabilityScanner` with:

```swift
final class CameraCapabilityScanner {
    func scan() -> CameraCapabilityReport
}
```

- [ ] **Step 2: Implement AVFoundation discovery**

Use `AVCaptureDevice.DiscoverySession` for common video device types and convert devices/formats into `CameraDeviceSummary` and `CameraFormatSummary`.

- [ ] **Step 3: Show scan results in the UI**

Render devices, formats, `isMultiCamSupported`, and multi-camera sets in `ContentView`.

- [ ] **Step 4: Build and commit**

Run generic iOS build. Expected: build exits 0.

```bash
git add DualCamera/Services/CameraCapabilityScanner.swift DualCamera/Views/ContentView.swift
git commit -m "Add camera capability scanning"
```

## Task 5: Implement Single-Camera Preview

**Files:**
- Create: `DualCamera/Services/CameraSessionController.swift`
- Create: `DualCamera/Views/PreviewView.swift`
- Modify: `DualCamera/Views/ContentView.swift`

- [ ] **Step 1: Add session controller state**

Create an observable `CameraSessionController` that exposes `session`, `isRunning`, `diagnostics`, and selected device IDs.

- [ ] **Step 2: Add preview host**

Create `PreviewView` backed by `AVCaptureVideoPreviewLayer`.

- [ ] **Step 3: Configure single-camera session**

Implement `startSingleCamera(deviceID:)` and `stop()`.

- [ ] **Step 4: Build and commit**

Run generic iOS build. Expected: build exits 0.

```bash
git add DualCamera/Services/CameraSessionController.swift DualCamera/Views/PreviewView.swift DualCamera/Views/ContentView.swift
git commit -m "Add single camera preview"
```

## Task 6: Implement Multi-Camera Preview

**Files:**
- Modify: `DualCamera/Services/CameraSessionController.swift`
- Modify: `DualCamera/Views/ContentView.swift`

- [ ] **Step 1: Add dual-camera API**

Add:

```swift
func startMultiCamera(primaryID: String, secondaryID: String)
```

- [ ] **Step 2: Configure `AVCaptureMultiCamSession`**

If `AVCaptureMultiCamSession.isMultiCamSupported` is false, log an error and return. Otherwise configure two camera inputs and preview outputs.

- [ ] **Step 3: Surface runtime failures**

Observe runtime error, interruption, pressure, and thermal notifications and append visible diagnostics.

- [ ] **Step 4: Build and commit**

Run generic iOS build. Expected: build exits 0.

```bash
git add DualCamera/Services/CameraSessionController.swift DualCamera/Views/ContentView.swift
git commit -m "Add multi camera preview"
```

## Task 7: Implement Photo Capture

**Files:**
- Create: `DualCamera/Services/PhotoCaptureController.swift`
- Modify: `DualCamera/Services/CameraSessionController.swift`
- Modify: `DualCamera/Views/ContentView.swift`

- [ ] **Step 1: Add photo capture button**

Wire the UI to call `capturePhoto()`.

- [ ] **Step 2: Implement `AVCapturePhotoOutput` capture**

Add a photo output when the active session supports it and save JPEG files in the app documents directory.

- [ ] **Step 3: Add snapshot fallback diagnostic**

When photo output is unavailable in the active configuration, append a diagnostic entry explaining that snapshot fallback is not yet available for that session state.

- [ ] **Step 4: Build and commit**

Run generic iOS build. Expected: build exits 0.

```bash
git add DualCamera/Services/PhotoCaptureController.swift DualCamera/Services/CameraSessionController.swift DualCamera/Views/ContentView.swift
git commit -m "Add photo capture"
```

## Task 8: Implement Composed Video Recording

**Files:**
- Create: `DualCamera/Services/VideoRecordingController.swift`
- Modify: `DualCamera/Services/CameraSessionController.swift`
- Modify: `DualCamera/Views/ContentView.swift`

- [ ] **Step 1: Add recording controls**

Add Start Recording and Stop Recording controls with visible output status.

- [ ] **Step 2: Implement composed recording path**

For version 1, record the active preview composition through `AVAssetWriter`. In single-camera mode, write the selected camera's video frames. In dual-camera mode, write the primary stream first and log that full visual composition is the active recording target once both streams provide synchronized sample buffers.

- [ ] **Step 3: Log output result**

Append a `CaptureResult` when recording finishes, including the `.mov` output path.

- [ ] **Step 4: Build and commit**

Run generic iOS build. Expected: build exits 0.

```bash
git add DualCamera/Services/VideoRecordingController.swift DualCamera/Services/CameraSessionController.swift DualCamera/Views/ContentView.swift
git commit -m "Add video recording"
```

## Task 9: Export Reports and Verify on Device

**Files:**
- Modify: `DualCamera/Views/ContentView.swift`
- Modify: `DualCamera/Services/CameraSessionController.swift`

- [ ] **Step 1: Add export button**

Export the latest report plus diagnostics and captures to the app documents directory.

- [ ] **Step 2: Build for connected iPhone**

Run:

```bash
xcodebuild -project DualCamera.xcodeproj -scheme DualCamera -destination 'id=00008140-001A24823A80801C' build
```

Expected: build exits 0.

- [ ] **Step 3: Run final simulator tests**

Run:

```bash
xcodebuild test -project DualCamera.xcodeproj -scheme DualCamera -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add DualCamera/Views/ContentView.swift DualCamera/Services/CameraSessionController.swift
git commit -m "Add report export and device verification"
```

## Self-Review

- Spec coverage: The plan covers scanning, multi-camera support, dense console UI, single and dual preview, photo capture, video recording, diagnostics, JSON export, and real-device verification.
- Known first-version compromise: dual-camera recording starts by writing the primary stream through `AVAssetWriter` while the `VideoRecordingController` owns the composition boundary. This keeps recording hardware validation inside version 1 and leaves synchronized two-stream pixel composition as the next focused refinement.
- Placeholder scan: no open placeholder steps remain.
- Type consistency: model names and controller names are consistent across tasks.
