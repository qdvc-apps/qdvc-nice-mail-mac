import AppKit
import SwiftUI
import NiceMailCore

/// The Emoji tab: favourites (in your order) or every emoji, with search,
/// labels and skin tones. Double-click or ⌘C copies the selected emoji. Add
/// Custom and Move Up/Down sit in the button bar under the table; Copy is
/// in the toolbar (docs/HIG.md §3).
struct EmojiTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            table
            ListControlBar {
                ListBarButton("Add Custom Emoji", systemImage: "plus",
                              help: "Add a pasted emoji to your favourites, such as one that isn\u{2019}t in the list") {
                    model.beginAddCustomEmoji()
                }
                ListBarSeparator()
                ListBarButton("Move Up", systemImage: "arrow.up",
                              help: "Move the selected favourite up (\u{2325}\u{2318}\u{2191})") {
                    model.moveFavourite(model.selectedEmojiID, by: -1)
                }
                .disabled(!model.canMove(model.selectedEmojiID, by: -1))
                ListBarButton("Move Down", systemImage: "arrow.down",
                              help: "Move the selected favourite down (\u{2325}\u{2318}\u{2193})") {
                    model.moveFavourite(model.selectedEmojiID, by: 1)
                }
                .disabled(!model.canMove(model.selectedEmojiID, by: 1))
            }
        }
        .searchable(text: $model.emojiQuery, placement: .toolbar, prompt: "Name, description or label")
        .onChange(of: model.emojiQuery) { model.refreshEmojiRows() }
        .onChange(of: model.emojiBlock) { model.refreshEmojiRows() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: $model.emojiBlock) {
                    ForEach(EmojiBlock.allCases) { block in
                        Text(block.title).tag(block)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Show your favourites, or every emoji")
            }
            ToolbarItem(placement: .primaryAction) {
                CopyToolbarButton(help: "Copy the selected emoji (\u{2318}C)",
                                  disabled: model.selectedEmojiID == nil) {
                    model.copyEmoji(model.selectedEmojiID)
                }
            }
        }
    }

    private var table: some View {
        @Bindable var model = model
        return Table(model.emojiRows, selection: $model.selectedEmojiID) {
            TableColumn("Emoji") { row in
                Text(row.symbol)
                    .font(.system(size: 20))
            }
            .width(min: 50, ideal: 64, max: 110)

            TableColumn("Name") { row in
                HStack(spacing: 6) {
                    Text(row.name)
                    if row.isCustom {
                        Text("\u{2014} custom emoji from your favourites")
                            .foregroundStyle(.secondary)
                    }
                }
                .help(row.id)
            }
            .width(min: 160, ideal: 420)

            TableColumn("User Label") { row in
                Text(row.label)
            }
            .width(min: 100, ideal: 200)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            EmojiMenuItems(id: ids.first)
        } primaryAction: { ids in
            model.copyEmoji(ids.first)
        }
        .onCopyCommand {
            guard let row = model.selectedEmoji else { return [] }
            model.noteCopied()
            return [NSItemProvider(object: row.symbol as NSString)]
        }
        .overlay {
            if model.emojiRows.isEmpty {
                if !model.emojiQuery.trimmed.isEmpty {
                    ContentUnavailableView.search(text: model.emojiQuery)
                } else {
                    ContentUnavailableView("No Favourites", systemImage: "star",
                                           description: Text("Choose All Emoji, then right-click an emoji and choose Add to Favourites."))
                }
            }
        }
    }
}

/// The emoji actions, shared by the table's context menu and the Emoji menu
/// in the menu bar.
struct EmojiMenuItems: View {
    @Environment(AppModel.self) private var model
    let id: String?

    var body: some View {
        let favourite = model.isFavourite(id)
        if favourite {
            Button("Remove from Favourites") { model.removeFavourite(id) }
        } else {
            Button("Add to Favourites") { model.addFavourite(id) }
                .disabled(id == nil)
        }
        Button("Set User Label\u{2026}") { model.beginSetLabel(id) }
            .disabled(!favourite)
        Divider()
        Button("Move Up") { model.moveFavourite(id, by: -1) }
            .disabled(!model.canMove(id, by: -1))
        Button("Move Down") { model.moveFavourite(id, by: 1) }
            .disabled(!model.canMove(id, by: 1))
        Divider()
        Button("Copy") { model.copyEmoji(id) }
            .disabled(id == nil)
    }
}
