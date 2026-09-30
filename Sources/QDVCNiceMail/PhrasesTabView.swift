import AppKit
import SwiftUI
import NiceMailCore

/// The Phrases tab: your phrases in alphabetical order, with search.
/// Double-click or ⌘C copies the selected phrase; Delete removes it. Add,
/// Delete and Edit sit in the button bar under the table; Copy is in the
/// toolbar (docs/HIG.md §3).
struct PhrasesTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            table
            ListControlBar {
                ListBarButton("Add Phrase", systemImage: "plus", help: "Add a phrase (\u{2318}N)") {
                    model.beginAddPhrase()
                }
                ListBarButton("Delete Phrase", systemImage: "minus",
                              help: "Delete the selected phrase (\u{232B})") {
                    model.beginDeletePhrase(model.selectedPhraseID)
                }
                .disabled(model.selectedPhraseID == nil)
                ListBarSeparator()
                ListBarButton("Edit Phrase", systemImage: "pencil", help: "Edit the selected phrase") {
                    model.beginEditPhrase(model.selectedPhraseID)
                }
                .disabled(model.selectedPhraseID == nil)
            }
        }
        .searchable(text: $model.phraseQuery, placement: .toolbar, prompt: "Search phrases")
        .onChange(of: model.phraseQuery) { model.refreshPhraseRows() }
        .alert("Delete this phrase?",
               isPresented: Binding(get: { model.phrasePendingDeletion != nil },
                                    set: { if !$0 { model.phrasePendingDeletion = nil } }),
               presenting: model.phrasePendingDeletion) { phrase in
            Button("Delete", role: .destructive) { model.performDeletePhrase(phrase.id) }
            Button("Cancel", role: .cancel) {}
        } message: { phrase in
            Text(phrase.text)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                CopyToolbarButton(help: "Copy the selected phrase (\u{2318}C)",
                                  disabled: model.selectedPhraseID == nil) {
                    model.copyPhrase(model.selectedPhraseID)
                }
            }
        }
    }

    private var table: some View {
        @Bindable var model = model
        return Table(model.phraseRows, selection: $model.selectedPhraseID) {
            TableColumn("Phrase") { phrase in
                Text(phrase.text)
                    .lineLimit(1)
                    .help(phrase.text)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            PhraseMenuItems(id: ids.first)
        } primaryAction: { ids in
            model.copyPhrase(ids.first)
        }
        .onCopyCommand {
            guard let phrase = model.selectedPhrase else { return [] }
            model.noteCopied()
            return [NSItemProvider(object: phrase.text as NSString)]
        }
        .onDeleteCommand {
            model.beginDeletePhrase(model.selectedPhraseID)
        }
        .overlay {
            if model.phraseRows.isEmpty {
                if !model.phraseQuery.trimmed.isEmpty {
                    ContentUnavailableView.search(text: model.phraseQuery)
                } else {
                    ContentUnavailableView {
                        Label("No Phrases", systemImage: "text.quote")
                    } description: {
                        Text("Add the sentences you type most, then copy them into any email.")
                    } actions: {
                        Button("Add Phrase\u{2026}") { model.beginAddPhrase() }
                    }
                }
            }
        }
    }
}

/// The phrase actions for the context menu.
struct PhraseMenuItems: View {
    @Environment(AppModel.self) private var model
    let id: String?

    var body: some View {
        Button("Copy") { model.copyPhrase(id) }
            .disabled(id == nil)
        Divider()
        Button("Edit\u{2026}") { model.beginEditPhrase(id) }
            .disabled(id == nil)
        Button("Delete\u{2026}") { model.beginDeletePhrase(id) }
            .disabled(id == nil)
        Divider()
        Button("Add Phrase\u{2026}") { model.beginAddPhrase() }
    }
}
