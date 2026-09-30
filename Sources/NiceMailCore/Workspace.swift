import Foundation

/// A workspace folder: the files are the database (port of
/// `qdvc/workspace.py`). The layout is documented in docs/FILE_FORMAT.md:
///
///     <workspace>/
///         favourite_emoji.csv        id,label,char
///         phrases.csv                id,text
///         mailsigs/
///             signoff.txt
///             disclaimer.txt
///             profiles/<name>.txt
///
/// Every mutation writes its file straight away (atomically), so there is
/// never unsaved state, and `scan()` can be called at any time to pick up
/// edits made elsewhere.
public final class Workspace: @unchecked Sendable {
    public let root: URL
    public let catalogue: EmojiCatalogue

    /// Favourite emoji ids in display order (significant; preserved on write).
    public private(set) var favouriteIDs: [String] = []
    /// Optional user label per favourite id.
    public private(set) var favouriteLabels: [String: String] = [:]
    /// Glyph per custom (pasted) favourite id.
    public private(set) var favouriteChars: [String: String] = [:]
    /// Phrases in file order (the Phrases tab sorts them for display).
    public private(set) var phrases: [Phrase] = []
    /// Profiles sorted by file name.
    public private(set) var profiles: [Profile] = []

    public init(root: URL, catalogue: EmojiCatalogue) {
        self.root = root.standardizedFileURL
        self.catalogue = catalogue
        scan()
    }

    // MARK: - Paths

    public var favouritesCSV: URL { root.appendingPathComponent("favourite_emoji.csv") }
    public var phrasesCSV: URL { root.appendingPathComponent("phrases.csv") }
    public var mailsigsDir: URL { root.appendingPathComponent("mailsigs", isDirectory: true) }
    public var profilesDir: URL { mailsigsDir.appendingPathComponent("profiles", isDirectory: true) }
    public var signoffTXT: URL { mailsigsDir.appendingPathComponent("signoff.txt") }
    public var disclaimerTXT: URL { mailsigsDir.appendingPathComponent("disclaimer.txt") }

    private var fm: FileManager { .default }

    private func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    // MARK: - Scaffolding

    /// Create any missing files and folders with the Python edition's
    /// defaults, including the one required default favourite (😊).
    public func ensureScaffold() throws {
        try fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)

        if !exists(favouritesCSV) {
            let fav = catalogue.all.first { $0.char == EmojiCatalogue.defaultFavouriteChar }
            let fid = fav?.id ?? Naming.emojiID("smiling face with smiling eyes")
            try writeFavourites([fid])
        }
        if !exists(phrasesCSV) {
            try writePhrases([
                Phrase(id: "thanks", text: "Thanks very much for your help."),
                Phrase(id: "follow_up", text: "Just following up on my previous email."),
            ])
        }
        if !exists(signoffTXT) {
            try writeTextAtomically("Kind regards,\n\nJohn Smith\n", to: signoffTXT)
        }
        if !exists(disclaimerTXT) {
            try writeTextAtomically("a disclaimer text goes here\n", to: disclaimerTXT)
        }
        // Hidden files (.DS_Store, ._ AppleDouble files) don't count.
        let entries = (try? fm.contentsOfDirectory(atPath: profilesDir.path)) ?? []
        if !entries.contains(where: { !$0.hasPrefix(".") }) {
            try writeTextAtomically("John Smith\nSpecialist and Superhero\nData by day, defeating villains by night\n",
                                    to: profilesDir.appendingPathComponent("default.txt"))
        }
    }

    // MARK: - Load

    /// Re-read favourites, phrases and profiles from disk.
    public func scan() {
        readFavourites()
        phrases = readPhrases()
        profiles = readProfiles()
    }

    private func readFavourites() {
        var ids: [String] = []
        var labels: [String: String] = [:]
        var chars: [String: String] = [:]
        if let text = readTextFile(favouritesCSV) {
            for row in CSV.parseWithHeader(text) {
                let fid = (row["id"] ?? "").pyStrip
                guard !fid.isEmpty, !ids.contains(fid) else { continue }
                ids.append(fid)
                let label = (row["label"] ?? "").pyStrip
                if !label.isEmpty { labels[fid] = label }
                // A glyph is stored only for custom (pasted) emoji.
                let char = (row["char"] ?? "").pyStrip
                if !char.isEmpty { chars[fid] = char }
            }
        }
        favouriteIDs = ids
        favouriteLabels = labels
        favouriteChars = chars
    }

    private func readPhrases() -> [Phrase] {
        guard let text = readTextFile(phrasesCSV) else { return [] }
        return CSV.parseWithHeader(text).compactMap { row in
            let pid = (row["id"] ?? "").pyStrip
            guard !pid.isEmpty else { return nil }
            return Phrase(id: pid, text: (row["text"] ?? "").pyStrip)
        }
    }

    private func readProfiles() -> [Profile] {
        guard let names = try? fm.contentsOfDirectory(atPath: profilesDir.path) else { return [] }
        var out: [Profile] = []
        for fn in names.sorted(by: codePointPrecedes) where fn.hasSuffix(".txt") && !fn.hasPrefix(".") {
            let url = profilesDir.appendingPathComponent(fn)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue,
                  let text = readTextFile(url) else { continue }
            var lines = text.universalNewlines.pySplitLines
            while let last = lines.last, last.pyStrip.isEmpty { lines.removeLast() }
            out.append(Profile(name: String(fn.dropLast(4)), lines: lines))
        }
        return out
    }

    /// A text file's contents as Python reads it (universal newlines), or ""
    /// if it can't be read.
    public func readText(_ url: URL) -> String {
        readTextFile(url)?.universalNewlines ?? ""
    }

    /// Everything before the m-dash (re-read on every call).
    public var signoff: String { readText(signoffTXT) }

    /// The disclaimer body (re-read on every call).
    public var disclaimer: String { readText(disclaimerTXT) }

    // MARK: - Favourites

    private func writeFavourites(_ ids: [String]) throws {
        var rows = [["id", "label", "char"]]
        for fid in ids {
            rows.append([fid, favouriteLabels[fid] ?? "", favouriteChars[fid] ?? ""])
        }
        try writeTextAtomically(CSV.format(rows), to: favouritesCSV)
    }

    /// Add a catalogue emoji to the end of the favourites. False if it is
    /// already a favourite.
    @discardableResult
    public func addFavourite(_ emojiID: String) throws -> Bool {
        guard !favouriteIDs.contains(emojiID) else { return false }
        favouriteIDs.append(emojiID)
        try writeFavourites(favouriteIDs)
        return true
    }

    /// Favourite an arbitrary pasted glyph. Returns its `custom_…` id, or nil
    /// if the glyph is blank or already a favourite. The glyph is stored in
    /// the `char` column so it survives a reload.
    @discardableResult
    public func addCustomFavourite(_ glyph: String) throws -> String? {
        let char = glyph.pyStrip
        guard !char.isEmpty else { return nil }
        let emoji = catalogue.makeCustom(char)
        guard !favouriteIDs.contains(emoji.id) else { return nil }
        favouriteIDs.append(emoji.id)
        favouriteChars[emoji.id] = char
        try writeFavourites(favouriteIDs)
        return emoji.id
    }

    @discardableResult
    public func removeFavourite(_ emojiID: String) throws -> Bool {
        guard let index = favouriteIDs.firstIndex(of: emojiID) else { return false }
        favouriteIDs.remove(at: index)
        favouriteLabels[emojiID] = nil
        favouriteChars[emojiID] = nil
        try writeFavourites(favouriteIDs)
        return true
    }

    /// Set (or, with a blank label, clear) a favourite's user label.
    public func setFavouriteLabel(_ emojiID: String, _ label: String) throws {
        guard favouriteIDs.contains(emojiID) else { return }
        let label = label.pyStrip
        favouriteLabels[emojiID] = label.isEmpty ? nil : label
        try writeFavourites(favouriteIDs)
    }

    public func favouriteLabel(_ emojiID: String) -> String {
        favouriteLabels[emojiID] ?? ""
    }

    /// Move a favourite up (-1) or down (+1). False if it can't move.
    @discardableResult
    public func moveFavourite(_ emojiID: String, by delta: Int) throws -> Bool {
        guard let i = favouriteIDs.firstIndex(of: emojiID) else { return false }
        let j = i + delta
        guard j >= 0, j < favouriteIDs.count else { return false }
        favouriteIDs.swapAt(i, j)
        try writeFavourites(favouriteIDs)
        return true
    }

    /// The Emoji for a favourite id: a catalogue entry, or a custom glyph.
    public func resolveEmoji(_ fid: String) -> Emoji? {
        if let emoji = catalogue.emoji(id: fid) { return emoji }
        if let char = favouriteChars[fid], !char.isEmpty { return catalogue.makeCustom(char) }
        return nil
    }

    /// Custom (pasted) favourites, in favourites order.
    public func customFavourites() -> [Emoji] {
        favouriteIDs.compactMap { fid in
            catalogue.emoji(id: fid) == nil ? resolveEmoji(fid) : nil
        }
    }

    /// Every favourite that can be resolved, in favourites order.
    public func favouriteEmoji() -> [Emoji] {
        favouriteIDs.compactMap(resolveEmoji)
    }

    // MARK: - Phrases

    private func writePhrases(_ list: [Phrase]) throws {
        var rows = [["id", "text"]]
        rows += list.map { [$0.id, $0.text] }
        try writeTextAtomically(CSV.format(rows), to: phrasesCSV)
        phrases = list
    }

    /// A new id from the first 32 characters of the text, made unique with
    /// `_2`, `_3`…. (As in the Python edition, text with no letters or digits
    /// gets the id "emoji", because the shared slug rule falls back to it.)
    private func uniquePhraseID(_ base: String) -> String {
        let slug = Naming.emojiID(base)
        let existing = Set(phrases.map(\.id))
        guard existing.contains(slug) else { return slug }
        var n = 2
        while existing.contains("\(slug)_\(n)") { n += 1 }
        return "\(slug)_\(n)"
    }

    @discardableResult
    public func addPhrase(_ text: String) throws -> Phrase {
        let phrase = Phrase(id: uniquePhraseID(text.pyPrefix(32)), text: text.pyStrip)
        try writePhrases(phrases + [phrase])
        return phrase
    }

    public func editPhrase(_ id: String, text: String) throws {
        var list = phrases
        if let i = list.firstIndex(where: { $0.id == id }) {
            list[i].text = text.pyStrip
        }
        try writePhrases(list)
    }

    public func deletePhrase(_ id: String) throws {
        try writePhrases(phrases.filter { $0.id != id })
    }

    /// Move a phrase up (-1) or down (+1) in file order. The UI sorts phrases
    /// alphabetically and doesn't use this; kept for parity.
    @discardableResult
    public func movePhrase(_ id: String, by delta: Int) throws -> Bool {
        guard let i = phrases.firstIndex(where: { $0.id == id }) else { return false }
        let j = i + delta
        guard j >= 0, j < phrases.count else { return false }
        var list = phrases
        list.swapAt(i, j)
        try writePhrases(list)
        return true
    }

    // MARK: - Profiles

    /// The named profile, or the first profile when the name is nil or
    /// unknown (nil when there are none).
    public func profile(named name: String?) -> Profile? {
        if let name, let match = profiles.first(where: { $0.name == name }) { return match }
        return profiles.first
    }

    // MARK: - Validation

    public struct Problems: Equatable, Sendable {
        /// Favourite ids that are neither in the catalogue nor custom glyphs.
        public var orphanFavourites: [String] = []
        /// Missing `signoff.txt` / `disclaimer.txt`.
        public var missingFiles: [String] = []
    }

    public func validate() -> Problems {
        var problems = Problems()
        for fid in favouriteIDs where catalogue.emoji(id: fid) == nil && (favouriteChars[fid] ?? "").isEmpty {
            problems.orphanFavourites.append(fid)
        }
        for (label, url) in [("signoff.txt", signoffTXT), ("disclaimer.txt", disclaimerTXT)] where !exists(url) {
            problems.missingFiles.append(label)
        }
        return problems
    }
}
