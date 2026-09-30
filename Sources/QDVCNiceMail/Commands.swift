import AppKit
import SwiftUI
import NiceMailCore

extension AppTab {
    /// ⌘1…⌘4, in tab order (Alt+1…4 in the Python edition).
    var shortcut: KeyEquivalent {
        switch self {
        case .emoji: return "1"
        case .phrases: return "2"
        case .signature: return "3"
        case .note: return "4"
        }
    }
}

/// Menu-bar commands. Standard items (Edit, Window, Help, Settings…, Quit,
/// About) come from the system; these add the workspace and tab actions.
struct NiceMailCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Workspace\u{2026}") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.self) { path in
                    Button((path as NSString).abbreviatingWithTildeInPath) {
                        model.open(URL(fileURLWithPath: path, isDirectory: true))
                    }
                }
                if !model.recentWorkspaces.isEmpty {
                    Divider()
                    Button("Clear Menu") { model.clearRecents() }
                }
            }
            Button("Reveal Workspace in Finder") { model.revealWorkspace() }
                .disabled(model.workspace == nil)
            Divider()
            Button("New Phrase\u{2026}") {
                model.currentTab = .phrases
                model.beginAddPhrase()
            }
            .keyboardShortcut("n")
            .disabled(model.workspace == nil)
            Button("Send Note to Self\u{2026}") { model.sendNote() }
                .keyboardShortcut("s")
                .disabled(model.workspace == nil || model.currentTab != .note)
            Divider()
            Button("Close Workspace") { model.closeWorkspace() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model.workspace == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            // ⌘C copies whatever has focus (a table row, selected text, or the
            // whole signature); this always copies the tab's item.
            Button("Copy from Current Tab") { model.copyCurrentTab() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!model.canCopyCurrentTab)
        }

        CommandGroup(after: .toolbar) {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) { model.currentTab = tab }
                    .keyboardShortcut(tab.shortcut)
                    .disabled(model.workspace == nil)
            }
            Divider()
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.workspace == nil)
            Button("New Message Ref") { model.newMessageRef() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.workspace == nil || !model.currentTab.hasMessageRef)
            Divider()
        }

        CommandMenu("Emoji") {
            // Acts on the Emoji tab's selection, so only there.
            let id = model.currentTab == .emoji ? model.selectedEmojiID : nil
            let favourite = model.isFavourite(id)
            Button(favourite ? "Remove from Favourites" : "Add to Favourites") {
                if favourite { model.removeFavourite(id) } else { model.addFavourite(id) }
            }
            .keyboardShortcut("d")
            .disabled(id == nil)
            Button("Set User Label\u{2026}") { model.beginSetLabel(id) }
                .keyboardShortcut("l")
                .disabled(!favourite)
            Divider()
            Button("Move Up") { model.moveFavourite(id, by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!model.canMove(id, by: -1))
            Button("Move Down") { model.moveFavourite(id, by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!model.canMove(id, by: 1))
            Divider()
            Button("Add Custom Emoji\u{2026}") {
                model.currentTab = .emoji
                model.beginAddCustomEmoji()
            }
            .disabled(model.workspace == nil)
        }
    }
}
