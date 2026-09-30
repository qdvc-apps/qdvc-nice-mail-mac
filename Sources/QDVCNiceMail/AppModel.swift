import AppKit
import Observation
import UniformTypeIdentifiers
import NiceMailCore

/// The window's tabs (the segmented control in the toolbar).
enum AppTab: String, CaseIterable, Identifiable {
    case emoji, phrases, signature, note

    var id: Self { self }

    var title: String {
        switch self {
        case .emoji: return "Emoji"
        case .phrases: return "Phrases"
        case .signature: return "Signature"
        case .note: return "Note to Self"
        }
    }

    /// Tabs that have a message ref (New Ref, and Refresh makes a new one).
    var hasMessageRef: Bool { self == .signature || self == .note }

    /// Tabs with a search field.
    var isSearchable: Bool { self == .emoji || self == .phrases }
}

/// Which emoji the Emoji tab lists.
enum EmojiBlock: String, CaseIterable, Identifiable {
    case favourites, all

    var id: Self { self }

    var title: String { self == .favourites ? "Favourites" : "All Emoji" }
}

/// A value snapshot of one Emoji-tab row.
struct EmojiRow: Identifiable, Hashable {
    let id: String
    /// The glyph as shown and copied (with the skin tone applied).
    let symbol: String
    let name: String
    let label: String
    let isFavourite: Bool
    let isCustom: Bool
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// The one sheet that can be open over the main window.
enum ActiveSheet: Identifiable {
    case addCustomEmoji
    case setLabel(String)
    case addPhrase
    case editPhrase(String)

    var id: String {
        switch self {
        case .addCustomEmoji: return "add-custom"
        case .setLabel(let id): return "label-\(id)"
        case .addPhrase: return "add-phrase"
        case .editPhrase(let id): return "edit-phrase-\(id)"
        }
    }
}

/// All state for the single main window. Every change to the workspace goes
/// through here, and the matching `refresh…` method rebuilds what the views
/// show, so rows, counts and previews stay in step.
@MainActor
@Observable
final class AppModel {
    /// Built once: scanning the Unicode ranges takes a moment.
    let catalogue = EmojiCatalogue()

    // Workspace
    private(set) var workspace: Workspace?
    private(set) var recentWorkspaces: [String] = Prefs.recentWorkspaces
    var currentTab: AppTab = .emoji
    var activeSheet: ActiveSheet?
    var alert: AlertInfo?

    // Emoji tab
    var emojiBlock: EmojiBlock = .favourites
    var emojiQuery = ""
    private(set) var emojiRows: [EmojiRow] = []
    var selectedEmojiID: String?

    // Phrases tab
    var phraseQuery = ""
    private(set) var phraseRows: [Phrase] = []
    var selectedPhraseID: String?
    var phrasePendingDeletion: Phrase?

    // Signature tab
    private(set) var profileNames: [String] = []
    var profileName: String? = Prefs.profile
    var includeDisclaimer = Prefs.includeDisclaimer
    var refOnly = Prefs.refOnly
    private(set) var signatureRef = Naming.generateMessageRef()
    private(set) var signatureText = ""

    // Note to Self tab
    var noteAddress = Prefs.noteEmail
    var noteSubject = ""
    var noteBody = ""
    private(set) var noteRef = Naming.generateMessageRef()
    /// Bumped when the note is cleared, so the body editor resets its undo.
    private(set) var noteGeneration = 0

    /// True for a moment after anything is copied: the toolbar's Copy button
    /// shows a checkmark instead of its usual icon (docs/HIG.md §4).
    private(set) var justCopied = false
    @ObservationIgnored private var copiedTask: Task<Void, Never>?

    // MARK: - Derived

    /// The window title. It isn't shown in the toolbar (docs/HIG.md §2), but
    /// it names the window in the Window menu, Mission Control and VoiceOver.
    var windowTitle: String {
        workspace?.root.lastPathComponent ?? "QDVC Nice Mail"
    }

    var selectedEmoji: EmojiRow? {
        guard let id = selectedEmojiID else { return nil }
        return emojiRows.first { $0.id == id }
    }

    var selectedPhrase: Phrase? {
        guard let id = selectedPhraseID else { return nil }
        return phraseRows.first { $0.id == id }
    }

    /// Move Up/Down apply to favourites, in the Favourites list only.
    func canMove(_ id: String?, by delta: Int) -> Bool {
        guard emojiBlock == .favourites, let id, let ws = workspace,
              let i = ws.favouriteIDs.firstIndex(of: id) else { return false }
        return ws.favouriteIDs.indices.contains(i + delta)
    }

    func isFavourite(_ id: String?) -> Bool {
        guard let id else { return false }
        return workspace?.favouriteIDs.contains(id) ?? false
    }

    // MARK: - Workspace

    /// Called once when the window appears: opens a folder given on the
    /// command line (`swift run QDVCNiceMail sample-workspace`), or else
    /// reopens the last workspace if that preference is on.
    func startUp() {
        guard workspace == nil else { return }
        let argument = CommandLine.arguments.dropFirst().first { arg in
            var isDir: ObjCBool = false
            return !arg.hasPrefix("-") && FileManager.default.fileExists(atPath: arg, isDirectory: &isDir)
                && isDir.boolValue
        }
        if let argument {
            open(URL(fileURLWithPath: argument, isDirectory: true))
        } else if Prefs.reopenLast, let last = Prefs.lastWorkspace,
                  FileManager.default.fileExists(atPath: last) {
            open(URL(fileURLWithPath: last, isDirectory: true))
        }
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a workspace folder. Any missing files are created for you."
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func open(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            alert = AlertInfo(title: "Workspace folder not found",
                              message: (url.path as NSString).abbreviatingWithTildeInPath)
            removeRecent(url.path)
            return
        }
        let ws = Workspace(root: url, catalogue: catalogue)
        do {
            try ws.ensureScaffold()
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t set up the workspace", message: error.localizedDescription)
            return
        }
        ws.scan()
        workspace = ws
        let path = ws.root.path
        Prefs.lastWorkspace = path
        recentWorkspaces = [path] + recentWorkspaces.filter { $0 != path }
        Prefs.recentWorkspaces = recentWorkspaces
        recentWorkspaces = Prefs.recentWorkspaces

        selectedEmojiID = nil
        selectedPhraseID = nil
        refreshProfiles()
        refreshAll()
    }

    func closeWorkspace() {
        workspace = nil
        emojiRows = []
        phraseRows = []
        profileNames = []
        signatureText = ""
        selectedEmojiID = nil
        selectedPhraseID = nil
    }

    func clearRecents() {
        recentWorkspaces = []
        Prefs.recentWorkspaces = []
    }

    private func removeRecent(_ path: String) {
        recentWorkspaces.removeAll { $0 == path }
        Prefs.recentWorkspaces = recentWorkspaces
    }

    func revealWorkspace() {
        guard let ws = workspace else { return }
        Platform.revealInFinder(ws.root)
    }

    /// View → Refresh (⌘R): re-read the workspace; on the Signature and Note
    /// to Self tabs, also start a new message ref (as in the Python edition).
    /// Those tabs' New Ref toolbar buttons are this same command.
    func refresh() {
        guard let ws = workspace else { return }
        ws.scan()
        refreshProfiles()
        refreshAll()
        if currentTab.hasMessageRef { newMessageRef() }
    }

    private func refreshAll() {
        refreshEmojiRows()
        refreshPhraseRows()
        refreshSignature()
    }

    /// Run a workspace mutation, reporting a failed write in an alert.
    private func perform(_ what: String, _ action: (Workspace) throws -> Void) {
        guard let ws = workspace else { return }
        do {
            try action(ws)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t \(what)", message: error.localizedDescription)
        }
    }

    // MARK: - Emoji tab

    func refreshEmojiRows() {
        guard let ws = workspace else {
            emojiRows = []
            return
        }
        let tone = Prefs.skinTone
        var list = emojiBlock == .favourites ? ws.favouriteEmoji()
                                             : ws.customFavourites() + catalogue.all
        let q = emojiQuery.trimmed.lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q) || $0.id.contains(q)
                    || ws.favouriteLabel($0.id).lowercased().contains(q)
            }
        }
        let favourites = Set(ws.favouriteIDs)
        emojiRows = list.map { emoji in
            EmojiRow(id: emoji.id, symbol: emoji.display(skinTone: tone), name: emoji.name,
                     label: ws.favouriteLabel(emoji.id), isFavourite: favourites.contains(emoji.id),
                     isCustom: emoji.isCustom)
        }
        if let id = selectedEmojiID, !emojiRows.contains(where: { $0.id == id }) {
            selectedEmojiID = nil
        }
    }

    func copyEmoji(_ id: String?) {
        guard let row = emojiRows.first(where: { $0.id == id }) else { return }
        Platform.copy(row.symbol)
        noteCopied()
    }

    func addFavourite(_ id: String?) {
        guard let id else { return }
        perform("add the favourite") { ws in
            _ = try ws.addFavourite(id)
        }
        refreshEmojiRows()
    }

    func removeFavourite(_ id: String?) {
        guard let id else { return }
        perform("remove the favourite") { ws in
            _ = try ws.removeFavourite(id)
        }
        refreshEmojiRows()
    }

    func moveFavourite(_ id: String?, by delta: Int) {
        guard let id, canMove(id, by: delta) else { return }
        perform("move the favourite") { ws in _ = try ws.moveFavourite(id, by: delta) }
        refreshEmojiRows()
        selectedEmojiID = id
    }

    func beginAddCustomEmoji() {
        guard workspace != nil else { return }
        activeSheet = .addCustomEmoji
    }

    /// Returns a message to show in the sheet when the glyph can't be added.
    func performAddCustomEmoji(_ glyph: String) -> String? {
        guard let ws = workspace else { return nil }
        do {
            guard let id = try ws.addCustomFavourite(glyph) else {
                return glyph.trimmed.isEmpty ? "Paste an emoji first." : "That emoji is already a favourite."
            }
            activeSheet = nil
            refreshEmojiRows()
            selectedEmojiID = id
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    func beginSetLabel(_ id: String?) {
        guard let id, isFavourite(id) else { return }
        activeSheet = .setLabel(id)
    }

    func performSetLabel(_ id: String, _ label: String) {
        activeSheet = nil
        perform("set the label") { ws in try ws.setFavouriteLabel(id, label) }
        refreshEmojiRows()
        selectedEmojiID = id
    }

    // MARK: - Phrases tab

    func refreshPhraseRows() {
        guard let ws = workspace else {
            phraseRows = []
            return
        }
        // Alphabetical (case-insensitive) by text, as in the Python edition.
        var list = ws.phrases.enumerated()
            .sorted { lhs, rhs in
                let l = Array(lhs.element.text.lowercased().unicodeScalars.map(\.value))
                let r = Array(rhs.element.text.lowercased().unicodeScalars.map(\.value))
                if l == r { return lhs.offset < rhs.offset }
                return l.lexicographicallyPrecedes(r)
            }
            .map(\.element)
        let q = phraseQuery.trimmed.lowercased()
        if !q.isEmpty {
            list = list.filter { $0.text.lowercased().contains(q) }
        }
        phraseRows = list
        if let id = selectedPhraseID, !phraseRows.contains(where: { $0.id == id }) {
            selectedPhraseID = nil
        }
    }

    func copyPhrase(_ id: String?) {
        guard let phrase = phraseRows.first(where: { $0.id == id }) else { return }
        Platform.copy(phrase.text)
        noteCopied()
    }

    func beginAddPhrase() {
        guard workspace != nil else { return }
        activeSheet = .addPhrase
    }

    func performAddPhrase(_ text: String) {
        activeSheet = nil
        guard !text.trimmed.isEmpty else { return }
        var added: Phrase?
        perform("add the phrase") { ws in added = try ws.addPhrase(text) }
        refreshPhraseRows()
        if let added { selectedPhraseID = added.id }
    }

    func beginEditPhrase(_ id: String?) {
        guard let id, phraseRows.contains(where: { $0.id == id }) else { return }
        activeSheet = .editPhrase(id)
    }

    func performEditPhrase(_ id: String, _ text: String) {
        activeSheet = nil
        guard !text.trimmed.isEmpty else { return }
        perform("save the phrase") { ws in try ws.editPhrase(id, text: text) }
        refreshPhraseRows()
        selectedPhraseID = id
    }

    func phraseText(_ id: String) -> String {
        workspace?.phrases.first { $0.id == id }?.text ?? ""
    }

    func beginDeletePhrase(_ id: String?) {
        phrasePendingDeletion = phraseRows.first { $0.id == id }
    }

    func performDeletePhrase(_ id: String) {
        phrasePendingDeletion = nil
        perform("delete the phrase") { ws in try ws.deletePhrase(id) }
        refreshPhraseRows()
    }

    // MARK: - Signature tab

    private func refreshProfiles() {
        profileNames = workspace?.profiles.map(\.name) ?? []
        if let name = profileName, profileNames.contains(name) { return }
        profileName = profileNames.first
    }

    func refreshSignature() {
        guard let ws = workspace else {
            signatureText = ""
            return
        }
        signatureText = Signature.assemble(signoff: ws.signoff, profile: ws.profile(named: profileName),
                                           disclaimer: ws.disclaimer,
                                           includeDisclaimer: includeDisclaimer,
                                           messageRef: signatureRef, refOnly: refOnly)
    }

    /// The Signature toolbar changed (profile, Disclaimer or Ref Only).
    func signatureOptionsChanged() {
        if let profileName { Prefs.profile = profileName }
        Prefs.includeDisclaimer = includeDisclaimer
        Prefs.refOnly = refOnly
        refreshSignature()
    }

    func copySignature() {
        guard workspace != nil else { return }
        Platform.copy(signatureText)
        noteCopied()
    }

    /// A new message ref for the current tab (the two refs are independent).
    private func newMessageRef() {
        switch currentTab {
        case .signature:
            signatureRef = Naming.generateMessageRef()
            refreshSignature()
        case .note:
            noteRef = Naming.generateMessageRef()
        default:
            break
        }
    }

    // MARK: - Note to Self tab

    func noteAddressChanged() {
        Prefs.noteEmail = noteAddress.trimmed
    }

    /// Save the note as a self-addressed .eml, then clear it and start a new
    /// message ref for the next one.
    func sendNote() {
        guard workspace != nil else { return }
        let data = Note.buildEML(address: noteAddress, subject: noteSubject, text: noteBody,
                                 messageRef: noteRef)
        let panel = NSSavePanel()
        panel.title = "Save Note as Email"
        panel.message = "Save the note to self as an .eml file you can open in Mail and send."
        panel.nameFieldStringValue = Note.defaultFilename(messageRef: noteRef)
        panel.allowedContentTypes = [UTType(filenameExtension: "eml") ?? .emailMessage]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alert = AlertInfo(title: "Couldn\u{2019}t save the note", message: error.localizedDescription)
            return
        }
        noteSubject = ""
        noteBody = ""
        noteGeneration += 1
        noteRef = Naming.generateMessageRef()
    }

    // MARK: - Copy

    /// Edit → Copy from Current Tab: the selected emoji or phrase, or the
    /// whole signature.
    func copyCurrentTab() {
        switch currentTab {
        case .emoji: copyEmoji(selectedEmojiID)
        case .phrases: copyPhrase(selectedPhraseID)
        case .signature: copySignature()
        case .note: break
        }
    }

    var canCopyCurrentTab: Bool {
        switch currentTab {
        case .emoji: return selectedEmojiID != nil
        case .phrases: return selectedPhraseID != nil
        case .signature: return workspace != nil
        case .note: return false
        }
    }

    // MARK: - Copy feedback

    /// Show the checkmark on the Copy button for a moment. Called for every
    /// copy, whether from the button, ⌘C, a double-click or a menu.
    func noteCopied() {
        justCopied = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.justCopied = false
        }
    }
}
