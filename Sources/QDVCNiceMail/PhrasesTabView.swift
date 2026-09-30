import AppKit
import SwiftUI
import NiceMailCore

/// The Phrases tab: your phrases in alphabetical order, with search.
/// Double-click or ⌘C copies the selected phrase; Delete removes it.
struct PhrasesTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.phraseRows, selection: $model.selectedPhraseID) {
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
            model.flash("Phrase copied")
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
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.beginAddPhrase()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .help("Add a phrase (\u{2318}N)")

                Button {
                    model.beginEditPhrase(model.selectedPhraseID)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .labelStyle(.titleAndIcon)
                .help("Edit the selected phrase")
                .disabled(model.selectedPhraseID == nil)

                Button {
                    model.beginDeletePhrase(model.selectedPhraseID)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .labelStyle(.titleAndIcon)
                .help("Delete the selected phrase (\u{232B})")
                .disabled(model.selectedPhraseID == nil)

                Button {
                    model.copyPhrase(model.selectedPhraseID)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.titleAndIcon)
                .help("Copy the selected phrase (\u{2318}C)")
                .disabled(model.selectedPhraseID == nil)
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
