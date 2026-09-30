import Foundation

// Small helpers that let the ported Python code be written almost
// line-for-line with the same semantics. They work on Unicode scalars (code
// points), as Python strings do: Swift's `Character` would merge "\r\n" and
// emoji sequences into one element and change the results.

enum PyText {
    /// Code points for which Python's `str.isspace()` is true.
    static func isSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Line boundaries recognised by Python's `str.splitlines()`.
    static func isLineBreak(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }
}

extension String {
    /// Python's `str.strip()`.
    var pyStrip: String {
        let scalars = Array(unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && PyText.isSpace(scalars[start]) { start += 1 }
        while end > start && PyText.isSpace(scalars[end - 1]) { end -= 1 }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// Python's `str.rstrip(chars)` for a set of code points.
    func pyRStrip(_ chars: Set<Unicode.Scalar>) -> String {
        var scalars = Array(unicodeScalars)
        while let last = scalars.last, chars.contains(last) { scalars.removeLast() }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Python's `str.strip(chars)` for a set of code points.
    func pyStrip(_ chars: Set<Unicode.Scalar>) -> String {
        let scalars = Array(unicodeScalars)
        var start = 0
        var end = scalars.count
        while start < end && chars.contains(scalars[start]) { start += 1 }
        while end > start && chars.contains(scalars[end - 1]) { end -= 1 }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    /// Python's `str.splitlines()` (no line ends kept, no trailing empty item).
    var pySplitLines: [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var iterator = unicodeScalars.makeIterator()
        var pending = iterator.next()
        while let s = pending {
            pending = iterator.next()
            if PyText.isLineBreak(s) {
                lines.append(String(current))
                current = String.UnicodeScalarView()
                if s == "\r", pending == "\n" { pending = iterator.next() }
            } else {
                current.append(s)
            }
        }
        if !current.isEmpty { lines.append(String(current)) }
        return lines
    }

    /// Python's `s[:n]`: the first `n` code points.
    func pyPrefix(_ n: Int) -> String {
        String(String.UnicodeScalarView(unicodeScalars.prefix(n)))
    }

    /// Text as Python reads it from a file opened in text mode ("universal
    /// newlines"): "\r\n" and lone "\r" become "\n".
    var universalNewlines: String {
        guard contains("\r") else { return self }
        var out = String.UnicodeScalarView()
        var iterator = unicodeScalars.makeIterator()
        var pending = iterator.next()
        while let s = pending {
            pending = iterator.next()
            if s == "\r" {
                out.append("\n")
                if pending == "\n" { pending = iterator.next() }
            } else {
                out.append(s)
            }
        }
        return String(out)
    }

    /// True when every code point is ASCII.
    var isASCII: Bool { unicodeScalars.allSatisfy(\.isASCII) }
}

/// Python's default string ordering (`sorted()` on `str`): by code point.
/// Swift's `<` on `String` compares canonically-equivalent forms instead.
func codePointPrecedes(_ a: String, _ b: String) -> Bool {
    a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) { $0.value < $1.value }
}

/// Atomically write UTF-8 text, creating the parent folder first. The Python
/// app writes to a `.tmp` sibling and `os.replace`s it; `.atomic` does the
/// same thing.
func writeTextAtomically(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url, options: .atomic)
}

/// Read a file as UTF-8, replacing invalid sequences. Returns nil when the
/// file cannot be read at all. No newline translation.
func readTextFile(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(decoding: data, as: UTF8.self)
}
