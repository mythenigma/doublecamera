import Foundation

/// Every user-facing string key in the app. Rendered text lives in
/// `Strings.table`; this enum just identifies which entry to look up.
enum LocKey: String {
    // Capture modes
    case modeSplit
    case modePip
    case modeDualFile
    case outputComposite
    case outputDualFile

    // Camera picker
    case pickerTitle
    case pickerStart
    case pickerSelectN

    // Lens names
    case lensUltraWide
    case lensTele
    case lensWide
    case lensSelfie

    // Capture screen
    case qualityLabel
    case fpsLabel
    case dualOrientationLabel
    case errorNoMultiCam
    case errorNeedPermission
    case buttonGrantPermission
    case fileTag1
    case fileTag2
    case warmupIndicator

    // Controller-reported errors
    case errMultiCamUnsupported
    case errNoCamerasFound
    case errIncompatiblePair
    case errCannotAddInput
    case errConfigFailed
    case errMicUnavailable
    case errFormatFailed
    case errLensSwitchFailedGeneric
    case errLensSwitchFailed
    case errZoomFailed
    case errFocusRangeFailed
    case errTorchFailed
    case errFocusFailed
    case errExposureFailed
    case errRecordStartFailed
    case errPhotoLibraryPermission
    case errPhotoLibrarySaveFailed
    case errUnknown
    case errPhotoSaveFailed
    case errPhotoSaveFailedGeneric

    // Runtime warnings
    case warnInterrupted
    case warnThermal

    // Settings
    case settingsTitle
    case settingsLanguageSection
    case settingsVideoFormatSection
    case formatHEVC
    case formatH264
    case settingsDeveloperConsole
    case settingsDone
}
