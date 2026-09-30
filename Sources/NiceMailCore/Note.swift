import Foundation

/// Note to Self: a self-addressed plaintext RFC 5322 message (port of
/// `qdvc/note.py`, which uses Python's `email` package).
///
/// The body is encoded exactly as Python's `EmailMessage.set_content` does
/// under the default policy (7bit, 8bit, quoted-printable or base64, chosen
/// by the same rules), with "\n" line endings. Headers match Python for
/// plain ASCII values; non-ASCII values become RFC 2047 encoded words that
/// decode to the same text, though Python may split them differently.
public enum Note {
    /// Longest header or body line before folding or re-encoding (Python's
    /// `policy.max_line_length`).
    static let maxLineLength = 78

    /// The body: the user's text without trailing newlines, two blank lines,
    /// the m-dash, a blank line, and the message-ref line (the same trailer
    /// as the Signature tab's Ref Only mode).
    public static func body(text: String, messageRef: String) -> String {
        let body = text.pyRStrip(["\n"])
        return "\(body)\n\n\n\(Signature.mdash)\n\nMessage ref. \(messageRef)\n"
    }

    /// The whole message as bytes. `address` is both From and To.
    public static func buildEML(address: String, subject: String, text: String,
                                messageRef: String, date: Date = Date(),
                                timeZone: TimeZone = .current) -> Data {
        let addr = address.pyStrip
        let (cte, payload) = encodeBody(body(text: text, messageRef: messageRef))
        var out = Data()
        func header(_ name: String, _ value: String) {
            out.append(Data(fold(name: name, tokens: value.isEmpty ? [] : headerTokens(value, address: name != "Subject")).utf8))
        }
        header("From", addr)
        header("To", addr)
        header("Subject", subject.pyStrip.replacingOccurrences(of: "\r", with: " ")
                                          .replacingOccurrences(of: "\n", with: " "))
        out.append(Data("Date: \(rfc5322Date(date, timeZone: timeZone))\n".utf8))
        out.append(Data("Content-Type: text/plain; charset=\"utf-8\"\n".utf8))
        out.append(Data("Content-Transfer-Encoding: \(cte)\n".utf8))
        out.append(Data("MIME-Version: 1.0\n\n".utf8))
        out.append(payload)
        return out
    }

    /// `yyyy-mm-dd-message-ref-<ref>.eml`, dated today.
    public static func defaultFilename(messageRef: String, date: Date = Date(),
                                       timeZone: TimeZone = .current) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d-message-ref-%@.eml",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, messageRef)
    }

    /// RFC 5322 date as Python's `email.utils.format_datetime`, e.g.
    /// "Wed, 30 Sep 2026 10:00:00 +0100".
    public static func rfc5322Date(_ date: Date, timeZone: TimeZone) -> String {
        let c = calendar(timeZone).dateComponents([.weekday, .year, .month, .day, .hour, .minute, .second],
                                                  from: date)
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let offset = timeZone.secondsFromGMT(for: date)
        let sign = offset < 0 ? "-" : "+"
        let minutes = abs(offset) / 60
        return String(format: "%@, %02d %@ %04d %02d:%02d:%02d %@%02d%02d",
                      days[(c.weekday ?? 1) - 1], c.day ?? 1, months[(c.month ?? 1) - 1], c.year ?? 1970,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, sign, minutes / 60, minutes % 60)
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    // MARK: - Body (Python's email.contentmanager._encode_text)

    /// Returns the Content-Transfer-Encoding and the encoded payload.
    static func encodeBody(_ string: String) -> (String, Data) {
        let lines = splitByteLines(Array(string.utf8))
        func joined(_ lines: ArraySlice<[UInt8]>) -> [UInt8] {
            var out: [UInt8] = []
            for line in lines {
                out += line
                out.append(0x0A)
            }
            if lines.isEmpty { out.append(0x0A) }
            return out
        }
        let normal = joined(lines[...])
        if (lines.map(\.count).max() ?? 0) <= maxLineLength {
            return (normal.allSatisfy { $0 < 0x80 } ? "7bit" : "8bit", Data(normal))
        }
        let sniff = joined(lines.prefix(10))
        let sniffQP = quotedPrintable(sniff, maxLineLength: maxLineLength)
        let sniffBase64Count = sniff.isEmpty ? 1 : Data(sniff).base64EncodedString().utf8.count + 1
        if sniffQP.count > sniffBase64Count {
            var payload = ""
            let perLine = maxLineLength / 4 * 3
            var start = 0
            repeat {
                let chunk = normal[start..<min(start + perLine, normal.count)]
                payload += Data(chunk).base64EncodedString() + "\n"
                start += perLine
            } while start < normal.count
            return ("base64", Data(payload.utf8))
        }
        if lines.count <= 10 {
            return ("quoted-printable", Data(sniffQP))
        }
        return ("quoted-printable", Data(quotedPrintable(normal, maxLineLength: maxLineLength)))
    }

    /// `bytes.splitlines()`: split on "\n", "\r" and "\r\n".
    static func splitByteLines(_ bytes: [UInt8]) -> [[UInt8]] {
        var lines: [[UInt8]] = []
        var current: [UInt8] = []
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x0A || b == 0x0D {
                lines.append(current)
                current = []
                if b == 0x0D, i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 1 }
            } else {
                current.append(b)
            }
            i += 1
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Python's `email.quoprimime.body_encode(body, maxlinelen)` with "\n"
    /// line endings, over the bytes of the body.
    static func quotedPrintable(_ body: [UInt8], maxLineLength maxlinelen: Int) -> [UInt8] {
        guard !body.isEmpty else { return [] }
        let hex = Array("0123456789ABCDEF".utf8)
        func quoted(_ b: UInt8) -> [UInt8] { [0x3D, hex[Int(b >> 4)], hex[Int(b & 0x0F)]] }
        // Quote special characters; tab, space, CR, LF and printable ASCII
        // other than "=" are kept.
        var translated: [UInt8] = []
        for b in body {
            if b == 0x09 || b == 0x0A || b == 0x0D || (0x20...0x7E).contains(b) && b != 0x3D {
                translated.append(b)
            } else {
                translated += quoted(b)
            }
        }
        let softBreak: [UInt8] = [0x3D, 0x0A]
        let maxlinelen1 = maxlinelen - 1
        var encoded: [[UInt8]] = []
        for line in splitByteLines(translated) {
            var start = 0
            let laststart = line.count - 1 - maxlinelen
            while start <= laststart {
                let stop = start + maxlinelen1
                // Never break inside an "=XX" escape.
                if line[stop - 2] == 0x3D {
                    encoded.append(Array(line[start..<(stop - 1)]))
                    start = stop - 2
                } else if line[stop - 1] == 0x3D {
                    encoded.append(Array(line[start..<stop]))
                    start = stop - 1
                } else {
                    encoded.append(Array(line[start..<stop]) + [0x3D])
                    start = stop
                }
            }
            if let last = line.last, last == 0x20 || last == 0x09 {
                // Whitespace at the end of a line must be protected.
                let room = start - laststart
                let q: [UInt8]
                if room >= 3 {
                    q = quoted(last)
                } else if room == 2 {
                    q = [last] + softBreak
                } else {
                    q = softBreak + quoted(last)
                }
                encoded.append(Array(line[start..<(line.count - 1)]) + q)
            } else {
                encoded.append(Array(line[min(start, line.count)...]))
            }
        }
        if let last = translated.last, last == 0x0A || last == 0x0D {
            encoded.append([])
        }
        var out: [UInt8] = []
        for (i, piece) in encoded.enumerated() {
            if i > 0 { out.append(0x0A) }
            out += piece
        }
        return out
    }

    // MARK: - Headers

    /// Split a header value into foldable tokens. ASCII words stay as they
    /// are; runs of words containing non-ASCII text become RFC 2047 encoded
    /// words. For an address header, a non-ASCII display name is encoded and
    /// the `<addr-spec>` kept, as Python does.
    static func headerTokens(_ value: String, address: Bool) -> [String] {
        if value.isASCII { return [value] }
        if address, let lt = value.lastIndex(of: "<"), value.hasSuffix(">") {
            var name = value[..<lt].pyStripString
            if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") {
                name = String(name.dropFirst().dropLast())
            }
            let spec = String(value[lt...])
            return (name.isEmpty ? [] : encodedWords(name)) + [spec]
        }
        var tokens: [String] = []
        var run: [String] = []
        func flushRun() {
            if !run.isEmpty { tokens += encodedWords(run.joined(separator: " ")) }
            run = []
        }
        for word in value.components(separatedBy: " ") where !word.isEmpty {
            if word.isASCII {
                flushRun()
                tokens.append(word)
            } else {
                run.append(word)
            }
        }
        flushRun()
        return tokens
    }

    /// "=?utf-8?q?...?=" or "=?utf-8?b?...?=" words, each at most 75
    /// characters, never splitting a character. Uses "q" unless it is at
    /// least five characters longer than "b" (Python's rule).
    static func encodedWords(_ text: String) -> [String] {
        let bytes = Array(text.utf8)
        let qSafe = Set(Array("-!*+/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8))
        func qLength(_ b: UInt8) -> Int { (qSafe.contains(b) || b == 0x20) ? 1 : 3 }
        let qLen = bytes.reduce(0) { $0 + qLength($1) }
        let bLen = (bytes.count + 2) / 3 * 4
        let useQ = qLen - bLen < 5
        let maxPayload = 75 - "=?utf-8?q??=".count

        func qEncode(_ chunk: [UInt8]) -> String {
            var s = ""
            for b in chunk {
                if b == 0x20 { s += "_" } else if qSafe.contains(b) { s += String(UnicodeScalar(b)) } else { s += String(format: "=%02X", b) }
            }
            return s
        }
        var words: [String] = []
        var chunk: [UInt8] = []
        func payloadLength(_ c: [UInt8]) -> Int {
            useQ ? c.reduce(0) { $0 + qLength($1) } : (c.count + 2) / 3 * 4
        }
        func flush() {
            guard !chunk.isEmpty else { return }
            let payload = useQ ? qEncode(chunk) : Data(chunk).base64EncodedString()
            words.append("=?utf-8?\(useQ ? "q" : "b")?\(payload)?=")
            chunk = []
        }
        for ch in text {
            let piece = Array(String(ch).utf8)
            if !chunk.isEmpty, payloadLength(chunk + piece) > maxPayload { flush() }
            chunk += piece
        }
        flush()
        return words
    }

    /// "Name: tokens…", folded before a token when the line would pass 78
    /// characters. An empty value gives "Name:" with no trailing space.
    static func fold(name: String, tokens: [String]) -> String {
        guard !tokens.isEmpty else { return "\(name):\n" }
        if tokens.count == 1, tokens[0].isASCII, !tokens[0].hasPrefix("=?") {
            // Plain ASCII: fold at spaces, keeping the original spacing.
            return foldASCII(name: name, value: tokens[0])
        }
        var out = "\(name):"
        var lineLength = out.count
        for token in tokens {
            if lineLength + 1 + token.count > maxLineLength, lineLength > name.count + 1 {
                out += "\n"
                lineLength = 0
            }
            out += " " + token
            lineLength += 1 + token.count
        }
        return out + "\n"
    }

    private static func foldASCII(name: String, value: String) -> String {
        let line = "\(name): \(value)"
        guard line.count > maxLineLength else { return line + "\n" }
        // Break at single spaces between words, greedily.
        let words = value.components(separatedBy: " ")
        var out = "\(name):"
        var lineLength = out.count
        var first = true
        for word in words {
            let piece = " " + word
            if !first, lineLength + piece.count > maxLineLength, !word.isEmpty {
                out += "\n"
                lineLength = 0
            }
            out += piece
            lineLength += piece.count
            first = false
        }
        return out + "\n"
    }
}

private extension Substring {
    var pyStripString: String { String(self).pyStrip }
}
