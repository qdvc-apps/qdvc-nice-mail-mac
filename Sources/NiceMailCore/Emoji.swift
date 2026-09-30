import Foundation

/// Fitzpatrick skin-tone modifiers. The raw values are the ids the Python
/// edition stores in its `skin_tone` preference.
public enum SkinTone: String, CaseIterable, Identifiable, Sendable {
    case none
    case light
    case mediumLight = "medium_light"
    case medium
    case mediumDark = "medium_dark"
    case dark

    public var id: String { rawValue }

    /// The modifier code point, or nil for `.none`.
    public var modifier: Unicode.Scalar? {
        switch self {
        case .none: return nil
        case .light: return "\u{1F3FB}"
        case .mediumLight: return "\u{1F3FC}"
        case .medium: return "\u{1F3FD}"
        case .mediumDark: return "\u{1F3FE}"
        case .dark: return "\u{1F3FF}"
        }
    }

    /// Labels as in the Python edition's `SKIN_TONE_LABELS`.
    public var label: String {
        switch self {
        case .none: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium-Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium-Dark"
        case .dark: return "Dark"
        }
    }
}

/// One emoji: a catalogue entry, or a custom glyph the user pasted in.
public struct Emoji: Hashable, Identifiable, Sendable {
    public let id: String
    /// The base character, without any skin-tone modifier.
    public let char: String
    /// Human-readable name (the Unicode name in Python's title case).
    public let name: String
    /// True for user-supplied (pasted) glyphs.
    public let isCustom: Bool

    public init(id: String, char: String, name: String, isCustom: Bool = false) {
        self.id = id
        self.char = char
        self.name = name
        self.isCustom = isCustom
    }

    /// The character with an optional skin-tone modifier applied. Custom
    /// glyphs are never changed.
    public func display(skinTone: SkinTone) -> String {
        guard let modifier = skinTone.modifier, !isCustom,
              EmojiCatalogue.acceptsSkinTone(char) else { return char }
        return char + String(Character(modifier))
    }
}

/// The full emoji list, keyed by snake_case id (port of `qdvc/emoji.py`).
///
/// Like the Python edition, it is built at runtime by scanning fixed
/// code-point ranges and naming every code point that has a Unicode name, so
/// the ids (including the `_2`, `_3` suffixes given to colliding names) are
/// the same in both editions and `favourite_emoji.csv` stays compatible. The
/// names come from the Swift standard library's Unicode data, so a newer macOS
/// may know a few more characters than an older one; it never renames them.
public final class EmojiCatalogue: @unchecked Sendable {
    /// Ranges scanned for candidate code points, in scan order.
    static let scanRanges: [ClosedRange<UInt32>] = [
        0x1F300...0x1FAFF,  // misc symbols, emoticons, transport, supplemental, extended-A
        0x2600...0x27BF,    // misc symbols + dingbats
        0x2190...0x21FF,    // arrows (a few are emoji-presented)
        0x2B00...0x2BFF,    // stars, etc.
    ]

    /// Code points that accept a skin-tone modifier: the Python edition's
    /// pragmatic list of people and body-part ranges.
    static let modifierBaseRanges: [ClosedRange<UInt32>] = [
        0x261D...0x261D, 0x26F9...0x26F9,
        0x270A...0x270D,
        0x1F385...0x1F385, 0x1F3C2...0x1F3C4, 0x1F3C7...0x1F3C7,
        0x1F3CA...0x1F3CC, 0x1F442...0x1F443, 0x1F446...0x1F450,
        0x1F466...0x1F478, 0x1F47C...0x1F47C, 0x1F481...0x1F483,
        0x1F485...0x1F487, 0x1F48F...0x1F48F, 0x1F491...0x1F491,
        0x1F4AA...0x1F4AA, 0x1F574...0x1F575, 0x1F57A...0x1F57A,
        0x1F590...0x1F590, 0x1F595...0x1F596, 0x1F645...0x1F647,
        0x1F64B...0x1F64F, 0x1F6A3...0x1F6A3, 0x1F6B4...0x1F6B6,
        0x1F6C0...0x1F6C0, 0x1F6CC...0x1F6CC, 0x1F918...0x1F91F,
        0x1F926...0x1F926, 0x1F930...0x1F939, 0x1F93C...0x1F93E,
        0x1F977...0x1F977, 0x1F9B5...0x1F9B6, 0x1F9B8...0x1F9B9,
        0x1F9BB...0x1F9BB, 0x1F9CD...0x1F9CF, 0x1F9D1...0x1F9DD,
    ]

    /// The single default favourite: 😊 SMILING FACE WITH SMILING EYES.
    public static let defaultFavouriteChar = "\u{1F60A}"

    /// Joiners and variation selectors skipped when naming a custom glyph.
    private static let nameSkip: Set<UInt32> = [0x200D, 0xFE0F, 0xFE0E]

    public let all: [Emoji]
    private let byID: [String: Emoji]

    public init() {
        var ordered: [Emoji] = []
        var byID: [String: Emoji] = [:]
        for range in Self.scanRanges {
            for cp in range {
                guard let scalar = Unicode.Scalar(cp), let name = scalar.properties.name else {
                    continue  // unnamed code point: not a usable emoji
                }
                let baseID = Naming.emojiID(name)
                var uid = baseID
                var n = 2
                while byID[uid] != nil {
                    uid = "\(baseID)_\(n)"
                    n += 1
                }
                let emoji = Emoji(id: uid, char: String(Character(scalar)), name: Self.pyTitle(name))
                byID[uid] = emoji
                ordered.append(emoji)
            }
        }
        all = ordered
        self.byID = byID
    }

    public func emoji(id: String) -> Emoji? { byID[id] }

    /// A custom Emoji for an arbitrary pasted glyph. Its name is assembled
    /// from the Unicode names of its code points (skipping joiners and
    /// variation selectors), so "❤️‍🩹" is searchable as
    /// "Heavy Black Heart + Adhesive Bandage".
    public func makeCustom(_ glyph: String) -> Emoji {
        var parts: [String] = []
        for scalar in glyph.unicodeScalars where !Self.nameSkip.contains(scalar.value) {
            if let name = scalar.properties.name { parts.append(Self.pyTitle(name)) }
        }
        let name = parts.isEmpty ? "Custom Emoji" : parts.joined(separator: " + ")
        return Emoji(id: Naming.customEmojiID(glyph), char: glyph, name: name, isCustom: true)
    }

    /// Case-insensitive substring match on the name or id.
    public func search(_ query: String) -> [Emoji] {
        let q = query.pyStrip.lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.id.contains(q) }
    }

    /// Whether the glyph's first code point takes a skin-tone modifier.
    public static func acceptsSkinTone(_ glyph: String) -> Bool {
        guard let first = glyph.unicodeScalars.first else { return false }
        return modifierBaseRanges.contains { $0.contains(first.value) }
    }

    /// Python's `str.title()` for the ASCII Unicode names: upper-case a
    /// letter that follows a non-letter, lower-case every other letter.
    static func pyTitle(_ s: String) -> String {
        var out = ""
        var previousCased = false
        for ch in s {
            if ch.isCased {
                out += previousCased ? ch.lowercased() : ch.uppercased()
                previousCased = true
            } else {
                out.append(ch)
                previousCased = false
            }
        }
        return out
    }
}
