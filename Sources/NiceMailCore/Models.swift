import Foundation

/// A reusable phrase from `phrases.csv`.
public struct Phrase: Hashable, Identifiable, Sendable {
    public let id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// A mail-signature profile loaded from `mailsigs/profiles/<name>.txt`.
public struct Profile: Hashable, Identifiable, Sendable {
    /// The file name without `.txt`, used as the profile picker's label.
    public let name: String
    /// The block that appears after the m-dash, one entry per line, with
    /// trailing blank lines removed.
    public let lines: [String]

    public var id: String { name }

    public init(name: String, lines: [String]) {
        self.name = name
        self.lines = lines
    }

    public var block: String { lines.joined(separator: "\n") }
}
