import Foundation

/// Drives the app's manually-selected display language. Defaults to English
/// on first launch — deliberately does not read the system locale — and
/// persists whatever the user picks in Settings.
final class LocalizationManager: ObservableObject, @unchecked Sendable {
    static let shared = LocalizationManager()

    private static let storageKey = "AppLanguage"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey), let stored = AppLanguage(rawValue: raw) {
            language = stored
        } else {
            language = .en
        }
    }

    func t(_ key: LocKey) -> String {
        Strings.table[key]?[language] ?? Strings.table[key]?[.en] ?? key.rawValue
    }

    func t(_ key: LocKey, _ arg0: String) -> String {
        t(key).replacingOccurrences(of: "{0}", with: arg0)
    }

    func t(_ key: LocKey, _ arg0: String, _ arg1: String) -> String {
        t(key)
            .replacingOccurrences(of: "{0}", with: arg0)
            .replacingOccurrences(of: "{1}", with: arg1)
    }
}
