import AppKit

/// Thin wrappers over AppKit services (the Mac counterpart of
/// `qdvc/platform_utils.py` and the GTK clipboard calls).
enum Platform {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Put keyboard focus in the window's toolbar search field (the one
    /// `.searchable` adds). Returns false when the window has none.
    @MainActor
    @discardableResult
    static func focusSearchField(in window: NSWindow?) -> Bool {
        guard let window else { return false }
        if let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first {
            item.beginSearchInteraction()
            return true
        }
        // Fall back to any search field in the window's frame, which holds the
        // toolbar as well as the content.
        guard let field = searchField(in: window.contentView?.superview ?? window.contentView) else {
            return false
        }
        window.makeFirstResponder(field)
        return true
    }

    @MainActor
    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField, !field.isHidden { return field }
        for subview in view.subviews {
            if let found = searchField(in: subview) { return found }
        }
        return nil
    }
}

extension String {
    /// The string without leading/trailing whitespace and newlines.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
