import Foundation

/// Languages the app can display, chosen manually in Settings. There is no
/// automatic system-locale detection — the app always starts in `.en` until
/// the user picks something else, and that choice persists.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case en, de, zh, ja, fr

    var id: String { rawValue }

    /// Always shown in the language's own name, matching how iOS itself
    /// lists languages in Settings — not translated by the current language.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        case .zh: return "中文"
        case .ja: return "日本語"
        case .fr: return "Français"
        }
    }
}
