import Foundation

/// Mail-signature assembly (port of `qdvc/mailsig.py`).
public enum Signature {
    public static let mdash = "\u{2014}"

    /// Assemble the plaintext signature:
    ///
    ///     <signoff>
    ///
    ///
    ///     —
    ///
    ///     <profile block>
    ///
    ///     [Disclaimer: <disclaimer>]
    ///
    ///     Message ref. <ref>
    ///
    /// Blocks are separated by one blank line, except that an extra blank line
    /// precedes the m-dash. The result ends with a newline. In `refOnly` mode
    /// the signature is just the m-dash, a blank line and the ref line.
    public static func assemble(signoff: String, profile: Profile?, disclaimer: String,
                                includeDisclaimer: Bool, messageRef: String,
                                refOnly: Bool = false) -> String {
        if refOnly {
            return "\(mdash)\n\nMessage ref. \(messageRef)\n"
        }
        var parts: [String] = []
        let so = signoff.pyRStrip(["\n"])
        if !so.isEmpty { parts.append(so) }
        // A newline before the m-dash yields two blank lines after the signoff.
        parts.append("\n" + mdash)
        if let profile, !profile.block.pyStrip.isEmpty {
            parts.append(profile.block.pyRStrip(["\n"]))
        }
        if includeDisclaimer {
            let d = disclaimer.pyStrip
            if !d.isEmpty { parts.append("Disclaimer: \(d)") }
        }
        parts.append("Message ref. \(messageRef)")
        return parts.joined(separator: "\n\n") + "\n"
    }
}
