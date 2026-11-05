import Foundation

/// Localized string lookup. Keys are English and live in `Localizable.xcstrings`.
/// A key without a translation falls back to the English key itself.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string (`%@`, `%d`, `%.1f` …).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

/// App language. By default the system language is used; an in-app override is stored in
/// the app's `AppleLanguages` default and takes effect after the app is restarted.
enum AppLanguage {
    /// Supported languages: the most widely used world languages + Turkish.
    static let supported: [(code: String, name: String)] = [
        ("en", "English"), ("zh-Hans", "简体中文"), ("hi", "हिन्दी"), ("es", "Español"), ("fr", "Français"),
        ("ar", "العربية"), ("pt-BR", "Português (Brasil)"), ("ru", "Русский"), ("de", "Deutsch"),
        ("ja", "日本語"), ("tr", "Türkçe"),
    ]

    /// The language the app is currently displayed in (e.g. "tr", "zh-Hans").
    static var current: String { Bundle.main.preferredLocalizations.first ?? "en" }

    /// In-app override (nil = follow the system language).
    static var override: String? {
        get {
            guard UserDefaults.standard.bool(forKey: "languageOverridden") else { return nil }
            return (UserDefaults.standard.array(forKey: "AppleLanguages") as? [String])?.first
        }
        set {
            if let newValue {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                UserDefaults.standard.set(true, forKey: "languageOverridden")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                UserDefaults.standard.set(false, forKey: "languageOverridden")
            }
        }
    }

    static func name(for code: String) -> String {
        supported.first { $0.code == code }?.name ?? code
    }

    /// Language code for OpenSubtitles searches (e.g. "tr", "zh-cn", "pt-br").
    static var subtitleCode: String {
        switch current {
        case "zh-Hans": return "zh-cn"
        case "pt-BR": return "pt-br"
        default: return String(current.prefix(2))
        }
    }

    /// Two-letter language code used to pick subtitle tracks ("tr", "zh", "pt" …).
    static var shortCode: String { String(current.prefix(2)) }
}
