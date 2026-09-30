import AppKit
import SwiftUI

/// The main window. As in Activity Monitor, Clock and Calendar, a segmented
/// control centred in the toolbar switches tabs (⌘1–⌘4). Each tab adds a
/// few toolbar items of its own (a picker at the leading edge, icon-only
/// actions and, for Emoji and Phrases, a search field at the trailing edge)
/// and keeps its other controls in the content; see docs/HIG.md. The welcome
/// screen shows when no workspace is open.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.workspace == nil {
                WelcomeView()
            } else {
                Group {
                    switch model.currentTab {
                    case .emoji: EmojiTabView()
                    case .phrases: PhrasesTabView()
                    case .signature: SignatureTabView()
                    case .note: NoteTabView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Tab", selection: $model.currentTab) {
                            ForEach(AppTab.allCases) { tab in
                                Text(tab.title).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Switch between Emoji, Phrases, Signature and Note to Self (\u{2318}1\u{2013}\u{2318}4)")
                    }
                }
                .onChange(of: model.currentTab) {
                    // Pick up edits made to the signature files in the meantime.
                    if model.currentTab == .signature { model.refreshSignature() }
                }
            }
        }
        // Names the window in the Window menu, Mission Control and VoiceOver;
        // the toolbar doesn't show it (see NiceMailApp and docs/HIG.md §2).
        .navigationTitle(model.windowTitle)
        .sheet(item: $model.activeSheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(model)
        }
        .alert(model.alert?.title ?? "",
               isPresented: Binding(get: { model.alert != nil },
                                    set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
    }
}

/// Picks the view for the sheet that is open. Sheets only collect input; the
/// AppModel method that applies the change also closes the sheet.
private struct SheetContent: View {
    @Environment(AppModel.self) private var model
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .addCustomEmoji:
            TextPromptSheet(title: "Add Custom Emoji",
                            message: "Paste an emoji that isn\u{2019}t in the list, such as one made of several parts like \u{2764}\u{FE0F}\u{200D}\u{1FA79}. It\u{2019}s added to your favourites and also listed under All Emoji.",
                            placeholder: "Paste an emoji", confirmTitle: "Add", allowsEmpty: false,
                            largeText: true) { glyph in
                model.performAddCustomEmoji(glyph)
            }
        case .setLabel(let id):
            let row = model.emojiRows.first { $0.id == id }
            TextPromptSheet(title: "Set User Label",
                            message: "A label for \(row?.symbol ?? "") \(row?.name ?? id). It\u{2019}s shown next to the emoji and matched by search. Leave it blank to remove the label.",
                            placeholder: "Label", confirmTitle: "Save",
                            initialText: model.workspace?.favouriteLabel(id) ?? "") { label in
                model.performSetLabel(id, label)
                return nil
            }
        case .addPhrase:
            TextPromptSheet(title: "Add Phrase", message: "A phrase you use often. Select it in the list and copy it into any email.",
                            placeholder: "Phrase", confirmTitle: "Add", allowsEmpty: false,
                            multiline: true) { text in
                model.performAddPhrase(text)
                return nil
            }
        case .editPhrase(let id):
            TextPromptSheet(title: "Edit Phrase", message: nil, placeholder: "Phrase", confirmTitle: "Save",
                            initialText: model.phraseText(id), allowsEmpty: false, multiline: true) { text in
                model.performEditPhrase(id, text)
                return nil
            }
        }
    }
}

/// A one-field sheet. `onConfirm` returns a problem to show (keeping the
/// sheet open), or nil when the change was made.
struct TextPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String?
    let placeholder: String
    let confirmTitle: String
    var allowsEmpty = true
    var multiline = false
    var largeText = false
    let onConfirm: (String) -> String?

    @State private var text: String
    @State private var problem: String?

    init(title: String, message: String?, placeholder: String, confirmTitle: String,
         initialText: String = "", allowsEmpty: Bool = true, multiline: Bool = false,
         largeText: Bool = false, onConfirm: @escaping (String) -> String?) {
        self.title = title
        self.message = message
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.allowsEmpty = allowsEmpty
        self.multiline = multiline
        self.largeText = largeText
        self.onConfirm = onConfirm
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
            }
            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(largeText ? Font.system(size: 22) : Font.body)
            .onChange(of: text) { problem = nil }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) {
                    problem = onConfirm(text)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!allowsEmpty && text.trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Shown when no workspace is open.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "envelope.open")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("QDVC Nice Mail")
                .font(.largeTitle.weight(.semibold))
            Text("Open a workspace folder to use your favourite emoji, phrases and signatures. An empty folder works too: the files you need are created for you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if !model.recentWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline)
                    ForEach(Array(model.recentWorkspaces.prefix(5)), id: \.self) { path in
                        Button((path as NSString).abbreviatingWithTildeInPath) {
                            model.open(URL(fileURLWithPath: path, isDirectory: true))
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            let folder = urls.first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            guard let url = folder else { return false }
            model.open(url)
            return true
        }
    }
}
