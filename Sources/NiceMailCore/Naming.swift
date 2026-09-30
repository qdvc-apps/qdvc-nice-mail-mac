import Foundation

/// Id and message-ref helpers (port of `qdvc/naming.py`).
public enum Naming {
    /// Deliberately excludes ambiguous glyphs (0/O, 1/l/I, 2/Z, 5/S, o/0, etc.).
    public static let messageRefAlphabet = "346789ABCDEFGHJKLMNPQRTUVWXYabcdefghijkmnpqrtwxyz"
    public static let messageRefLength = 10

    /// Snake_case id from an emoji's Unicode name: lower-case it, collapse
    /// every run of characters other than `a-z0-9` into one underscore, and
    /// trim underscores. An empty result becomes "emoji".
    ///
    ///     "GRINNING FACE WITH SMILING EYES" -> "grinning_face_with_smiling_eyes"
    public static func emojiID(_ name: String) -> String {
        var out = String.UnicodeScalarView()
        var inRun = false
        for s in name.pyStrip.lowercased().unicodeScalars {
            let v = s.value
            if (0x61...0x7A).contains(v) || (0x30...0x39).contains(v) {
                out.append(s)
                inRun = false
            } else if !inRun {
                out.append("_")
                inRun = true
            }
        }
        let id = String(out).pyStrip(["_"])
        return id.isEmpty ? "emoji" : id
    }

    /// Stable id for a user-supplied (pasted) glyph, from its code points in
    /// lower-case hex: "\u{2764}\u{FE0F}\u{200D}\u{1FA79}" -> "custom_2764_fe0f_200d_1fa79".
    public static func customEmojiID(_ glyph: String) -> String {
        let cps = glyph.unicodeScalars.map { String($0.value, radix: 16) }
        return cps.isEmpty ? "custom_emoji" : "custom_" + cps.joined(separator: "_")
    }

    /// A 10-character message ref from the unambiguous alphabet, drawn with
    /// the system's cryptographically secure generator (as Python's `secrets`).
    public static func generateMessageRef() -> String {
        var rng = SystemRandomNumberGenerator()
        return generateMessageRef(using: &rng)
    }

    public static func generateMessageRef<G: RandomNumberGenerator>(using rng: inout G) -> String {
        let alphabet = Array(messageRefAlphabet)
        return String((0..<messageRefLength).map { _ in alphabet.randomElement(using: &rng)! })
    }
}
