import SwiftUI

// Controls shared by the tabs, following docs/HIG.md: icon-only toolbar
// buttons for each tab's primary actions, the traditional macOS "+ −" button
// bar attached to the bottom left of a list, and a slim option bar under the
// toolbar.

/// Copy, as an icon-only toolbar button. It briefly becomes a checkmark after
/// anything is copied (`AppModel.justCopied`), which is the app's copy
/// confirmation now that there's no status text (docs/HIG.md §4).
struct CopyToolbarButton: View {
    @Environment(AppModel.self) private var model
    let help: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(model.justCopied ? "Copied" : "Copy",
                  systemImage: model.justCopied ? "checkmark" : "doc.on.doc")
        }
        .help(help)
        .disabled(disabled)
    }
}

/// New Ref, as an icon-only toolbar button. A new message ref is a refresh of
/// the tab, so it uses the refresh symbol and runs View → Refresh (⌘R).
struct NewRefToolbarButton: View {
    @Environment(AppModel.self) private var model
    let help: String

    var body: some View {
        Button {
            model.refresh()
        } label: {
            Label("New Ref", systemImage: "arrow.clockwise")
        }
        .help(help)
    }
}

/// The small button bar attached to the bottom edge of a list, with its
/// buttons at the left, as in System Settings and Mail → Settings → Accounts.
struct ListControlBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                content
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .frame(height: 28)
        }
        .background(.bar)
    }
}

/// One icon-only button in a `ListControlBar`. The title is kept for
/// VoiceOver; the tooltip says what the button does.
struct ListBarButton: View {
    let title: String
    let systemImage: String
    let help: String
    let action: () -> Void

    init(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}

/// A thin separator between groups of buttons in a `ListControlBar`.
struct ListBarSeparator: View {
    var body: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }
}

/// A slim, left-aligned bar of options under the toolbar and above the
/// content, like Preview's Markup toolbar.
struct OptionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
        }
        .background(.bar)
    }
}
