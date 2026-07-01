import Foundation

/// All translated strings, keyed by `LocKey` then `AppLanguage`.
/// Messages that need an inserted value use "{0}" / "{1}" placeholders,
/// substituted by `LocalizationManager.t(_:_:)`.
enum Strings {
    static let table: [LocKey: [AppLanguage: String]] = [
        // MARK: Capture modes
        .modeSplit: [
            .en: "Split", .de: "Split", .zh: "分割", .ja: "分割", .fr: "Division"
        ],
        .modePip: [
            .en: "PIP", .de: "PIP", .zh: "画中画", .ja: "PinP", .fr: "PIP"
        ],
        .modeDualFile: [
            .en: "Dual Rec", .de: "Dual-Rec", .zh: "双录", .ja: "デュアル録画", .fr: "Double Enr."
        ],
        .outputComposite: [
            .en: "Merged into 1 file", .de: "Zu 1 Datei zusammengeführt", .zh: "合成 1 个文件",
            .ja: "1つのファイルに結合", .fr: "Fusionné en 1 fichier"
        ],
        .outputDualFile: [
            .en: "2 separate files", .de: "2 separate Dateien", .zh: "独立 2 个文件",
            .ja: "2つの独立ファイル", .fr: "2 fichiers séparés"
        ],

        // MARK: Camera picker
        .pickerTitle: [
            .en: "Choose Your Cameras", .de: "Wähle deine Kameras", .zh: "选择您的相机",
            .ja: "カメラを選択", .fr: "Choisissez vos caméras"
        ],
        .pickerStart: [
            .en: "Start", .de: "Start", .zh: "开始", .ja: "開始", .fr: "Démarrer"
        ],
        .pickerSelectN: [
            .en: "Select 2 cameras ({0}/2)", .de: "Wähle 2 Kameras ({0}/2)", .zh: "请选择 2 个相机 ({0}/2)",
            .ja: "2台のカメラを選択 ({0}/2)", .fr: "Sélectionnez 2 caméras ({0}/2)"
        ],

        // MARK: Lens names
        .lensUltraWide: [
            .en: "Ultra Wide", .de: "Ultraweit", .zh: "超广角", .ja: "超広角", .fr: "Ultra grand-angle"
        ],
        .lensTele: [
            .en: "Tele", .de: "Tele", .zh: "长焦", .ja: "望遠", .fr: "Téléobjectif"
        ],
        .lensWide: [
            .en: "Wide", .de: "Weitwinkel", .zh: "广角", .ja: "広角", .fr: "Grand-angle"
        ],
        .lensSelfie: [
            .en: "Selfie", .de: "Selfie", .zh: "自拍", .ja: "自撮り", .fr: "Selfie"
        ],

        // MARK: Capture screen
        .qualityLabel: [
            .en: "Quality", .de: "Qualität", .zh: "画质", .ja: "画質", .fr: "Qualité"
        ],
        .fpsLabel: [
            .en: "Frame Rate", .de: "Bildrate", .zh: "帧率", .ja: "フレームレート", .fr: "Fréquence d'images"
        ],
        .dualOrientationLabel: [
            .en: "Portrait + Landscape", .de: "Hoch + Quer", .zh: "竖横同拍",
            .ja: "縦横同時撮影", .fr: "Portrait + Paysage"
        ],
        .errorNoMultiCam: [
            .en: "This device doesn't support dual-camera recording",
            .de: "Dieses Gerät unterstützt keine Doppelkamera-Aufnahme",
            .zh: "此设备不支持双摄像头同时录制",
            .ja: "この端末はデュアルカメラ録画に対応していません",
            .fr: "Cet appareil ne prend pas en charge l'enregistrement à double caméra"
        ],
        .errorNeedPermission: [
            .en: "Camera access required", .de: "Kamerazugriff erforderlich", .zh: "需要相机权限",
            .ja: "カメラへのアクセスが必要です", .fr: "Accès à la caméra requis"
        ],
        .buttonGrantPermission: [
            .en: "Grant Access", .de: "Zugriff erlauben", .zh: "授予权限",
            .ja: "アクセスを許可", .fr: "Autoriser l'accès"
        ],
        .fileTag1: [
            .en: "File 1", .de: "Datei 1", .zh: "文件 ①", .ja: "ファイル①", .fr: "Fichier 1"
        ],
        .fileTag2: [
            .en: "File 2", .de: "Datei 2", .zh: "文件 ②", .ja: "ファイル②", .fr: "Fichier 2"
        ],
        .warmupIndicator: [
            .en: "Focusing…", .de: "Fokussieren…", .zh: "对焦中…",
            .ja: "フォーカス調整中…", .fr: "Mise au point…"
        ],

        // MARK: Controller-reported errors
        .errMultiCamUnsupported: [
            .en: "This device doesn't support dual-camera recording (MultiCam unsupported).",
            .de: "Dieses Gerät unterstützt keine Doppelkamera-Aufnahme (MultiCam nicht unterstützt).",
            .zh: "此设备不支持双摄像头同时录制 (MultiCam unsupported).",
            .ja: "この端末はデュアルカメラ録画に対応していません（MultiCam非対応）。",
            .fr: "Cet appareil ne prend pas en charge l'enregistrement à double caméra (MultiCam non pris en charge)."
        ],
        .errNoCamerasFound: [
            .en: "Couldn't find usable front/back cameras.",
            .de: "Keine nutzbaren Front-/Rückkameras gefunden.",
            .zh: "找不到可用的前后摄像头。",
            .ja: "使用可能な前面/背面カメラが見つかりません。",
            .fr: "Impossible de trouver des caméras avant/arrière utilisables."
        ],
        .errIncompatiblePair: [
            .en: "These two cameras can't run together — please choose a different pair.",
            .de: "Diese beiden Kameras können nicht gleichzeitig laufen – bitte wähle eine andere Kombination.",
            .zh: "这两个摄像头不能同时运行，请重新选择一对。",
            .ja: "この2つのカメラは同時に使用できません。別の組み合わせを選んでください。",
            .fr: "Ces deux caméras ne peuvent pas fonctionner ensemble — veuillez choisir une autre paire."
        ],
        .errCannotAddInput: [
            .en: "Couldn't add camera input.",
            .de: "Kameraeingang konnte nicht hinzugefügt werden.",
            .zh: "无法添加摄像头输入。",
            .ja: "カメラ入力を追加できませんでした。",
            .fr: "Impossible d'ajouter l'entrée caméra."
        ],
        .errConfigFailed: [
            .en: "Configuration failed: {0}", .de: "Konfiguration fehlgeschlagen: {0}", .zh: "配置失败: {0}",
            .ja: "設定に失敗しました: {0}", .fr: "Échec de la configuration : {0}"
        ],
        .errMicUnavailable: [
            .en: "Microphone unavailable — recording without audio.",
            .de: "Mikrofon nicht verfügbar – Aufnahme ohne Ton.",
            .zh: "麦克风不可用，将录制无声视频。",
            .ja: "マイクが使用できません。音声なしで録画します。",
            .fr: "Microphone indisponible — enregistrement sans son."
        ],
        .errFormatFailed: [
            .en: "Couldn't set quality format for {0}: {1}",
            .de: "Qualitätsformat für {0} konnte nicht festgelegt werden: {1}",
            .zh: "无法设置 {0} 的画质格式: {1}",
            .ja: "{0} の画質フォーマットを設定できませんでした: {1}",
            .fr: "Impossible de définir le format de qualité pour {0} : {1}"
        ],
        .errLensSwitchFailedGeneric: [
            .en: "Couldn't switch to that lens.",
            .de: "Konnte nicht zu diesem Objektiv wechseln.",
            .zh: "无法切换到该镜头。",
            .ja: "そのレンズに切り替えられませんでした。",
            .fr: "Impossible de passer à cet objectif."
        ],
        .errLensSwitchFailed: [
            .en: "Lens switch failed: {0}", .de: "Objektivwechsel fehlgeschlagen: {0}", .zh: "切换镜头失败: {0}",
            .ja: "レンズの切り替えに失敗しました: {0}", .fr: "Échec du changement d'objectif : {0}"
        ],
        .errZoomFailed: [
            .en: "Couldn't set zoom: {0}", .de: "Zoom konnte nicht eingestellt werden: {0}", .zh: "无法设置变焦: {0}",
            .ja: "ズームを設定できませんでした: {0}", .fr: "Impossible de régler le zoom : {0}"
        ],
        .errFocusRangeFailed: [
            .en: "Couldn't set focus range: {0}",
            .de: "Fokusbereich konnte nicht eingestellt werden: {0}",
            .zh: "无法设置对焦范围: {0}",
            .ja: "フォーカス範囲を設定できませんでした: {0}",
            .fr: "Impossible de définir la plage de mise au point : {0}"
        ],
        .errTorchFailed: [
            .en: "Couldn't toggle torch: {0}", .de: "Blitzlicht konnte nicht umgeschaltet werden: {0}",
            .zh: "无法切换手电筒: {0}", .ja: "ライトを切り替えられませんでした: {0}",
            .fr: "Impossible d'activer la torche : {0}"
        ],
        .errFocusFailed: [
            .en: "Focus failed: {0}", .de: "Fokussierung fehlgeschlagen: {0}", .zh: "对焦失败: {0}",
            .ja: "フォーカスに失敗しました: {0}", .fr: "Échec de la mise au point : {0}"
        ],
        .errExposureFailed: [
            .en: "Exposure adjustment failed: {0}", .de: "Belichtungsanpassung fehlgeschlagen: {0}",
            .zh: "曝光调节失败: {0}", .ja: "露出調整に失敗しました: {0}",
            .fr: "Échec du réglage de l'exposition : {0}"
        ],
        .errRecordStartFailed: [
            .en: "Couldn't start recording: {0}", .de: "Aufnahme konnte nicht gestartet werden: {0}",
            .zh: "无法开始录制: {0}", .ja: "録画を開始できませんでした: {0}",
            .fr: "Impossible de démarrer l'enregistrement : {0}"
        ],
        .errPhotoLibraryPermission: [
            .en: "No permission to save to Photos — this capture is only saved in-app.",
            .de: "Keine Berechtigung zum Speichern in Fotos – diese Aufnahme wird nur in der App gespeichert.",
            .zh: "没有相册写入权限，本次拍摄仅保存在应用内。",
            .ja: "写真への保存権限がありません。今回の撮影はアプリ内にのみ保存されます。",
            .fr: "Aucune autorisation d'enregistrer dans Photos — cette capture n'est enregistrée que dans l'application."
        ],
        .errPhotoLibrarySaveFailed: [
            .en: "Couldn't save to Photos: {0}", .de: "Speichern in Fotos fehlgeschlagen: {0}",
            .zh: "保存到相册失败: {0}", .ja: "写真への保存に失敗しました: {0}",
            .fr: "Échec de l'enregistrement dans Photos : {0}"
        ],
        .errUnknown: [
            .en: "Unknown error", .de: "Unbekannter Fehler", .zh: "未知错误",
            .ja: "不明なエラー", .fr: "Erreur inconnue"
        ],
        .errPhotoSaveFailed: [
            .en: "Couldn't save photo: {0}", .de: "Foto konnte nicht gespeichert werden: {0}",
            .zh: "拍照保存失败: {0}", .ja: "写真を保存できませんでした: {0}",
            .fr: "Impossible d'enregistrer la photo : {0}"
        ],
        .errPhotoSaveFailedGeneric: [
            .en: "Photo capture failed — couldn't save the image.",
            .de: "Fotoaufnahme fehlgeschlagen – Bild konnte nicht gespeichert werden.",
            .zh: "拍照失败：无法保存图片。",
            .ja: "写真の撮影に失敗しました。画像を保存できませんでした。",
            .fr: "Échec de la capture photo — impossible d'enregistrer l'image."
        ],

        // MARK: Settings
        .settingsTitle: [
            .en: "Settings", .de: "Einstellungen", .zh: "设置", .ja: "設定", .fr: "Réglages"
        ],
        .settingsLanguageSection: [
            .en: "Language", .de: "Sprache", .zh: "语言", .ja: "言語", .fr: "Langue"
        ],
        .settingsDeveloperConsole: [
            .en: "Developer Console", .de: "Entwicklerkonsole", .zh: "开发者控制台",
            .ja: "開発者コンソール", .fr: "Console développeur"
        ],
        .settingsDone: [
            .en: "Done", .de: "Fertig", .zh: "完成", .ja: "完了", .fr: "Terminé"
        ]
    ]
}
