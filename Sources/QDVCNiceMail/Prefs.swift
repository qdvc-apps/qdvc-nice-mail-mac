import AppKit
import NiceMailCore

/// App preferences and remembered state, stored in the standard macOS
/// defaults domain (`defaults read org.qdvc.NiceMail`) rather than the Python
/// edition's `~/.config/qdvc-nicemail/config.yml`. Values that mean the same
/// thing in both editions (skin-tone ids, profile names) use the same values.
enum Prefs {
    enum Key {
        static let reopenLast = "reopenLastWorkspace"
        static let recentWorkspaces = "recentWorkspaces"
        static let lastWorkspace = "lastWorkspace"
        static let skinTone = "skinTone"
        static let profile = "profile"
        static let includeDisclaimer = "includeDisclaimer"
        static let refOnly = "refOnly"
        static let signatureFontFamily = "signatureFontFamily"
        static let signatureFontSize = "signatureFontSize"
        static let noteEmail = "noteEmail"
    }

    static let defaultFontSize = 13.0
    private static var defaults: UserDefaults { .standard }

    static var reopenLast: Bool {
        defaults.object(forKey: Key.reopenLast) as? Bool ?? true
    }

    static var recentWorkspaces: [String] {
        get { defaults.stringArray(forKey: Key.recentWorkspaces) ?? [] }
        set { defaults.set(Array(newValue.prefix(10)), forKey: Key.recentWorkspaces) }
    }

    static var lastWorkspace: String? {
        get { defaults.string(forKey: Key.lastWorkspace) }
        set { defaults.set(newValue, forKey: Key.lastWorkspace) }
    }

    static var skinTone: SkinTone {
        SkinTone(rawValue: defaults.string(forKey: Key.skinTone) ?? "") ?? SkinTone.none
    }

    static var profile: String? {
        get { defaults.string(forKey: Key.profile) }
        set { defaults.set(newValue, forKey: Key.profile) }
    }

    static var includeDisclaimer: Bool {
        get { defaults.object(forKey: Key.includeDisclaimer) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.includeDisclaimer) }
    }

    static var refOnly: Bool {
        get { defaults.bool(forKey: Key.refOnly) }
        set { defaults.set(newValue, forKey: Key.refOnly) }
    }

    static var noteEmail: String {
        get { defaults.string(forKey: Key.noteEmail) ?? "" }
        set { defaults.set(newValue, forKey: Key.noteEmail) }
    }

    /// The signature preview font (also used by the Note to Self fields): the
    /// chosen family, or the monospaced system font when none is set.
    static func signatureFont(family: String, size: Double) -> NSFont {
        let size = CGFloat(size > 0 ? size : defaultFontSize)
        if !family.isEmpty,
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
