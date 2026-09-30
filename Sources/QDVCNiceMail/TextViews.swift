import AppKit
import SwiftUI

// AppKit text views wrapped for SwiftUI. Both implement `sizeThatFits` and
// return the proposed size: without it SwiftUI falls back to the scroll view's
// AppKit fitting size, which can be huge and push the window layout out of
// shape (see docs/MAINTENANCE.md §3).

/// Puts a text view in a vertically scrolling scroll view, with its width
/// tracking the scroll view.
@MainActor
private func embedInScrollView(_ textView: NSTextView) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = true
    for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
        scrollView.setContentHuggingPriority(.defaultLow, for: orientation)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: orientation)
    }
    let size = scrollView.contentSize
    textView.frame = NSRect(origin: .zero, size: size)
    textView.minSize = .zero
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.containerSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    scrollView.documentView = textView
    return scrollView
}

/// A read-only text view whose Copy takes the whole text when nothing is
/// selected, so ⌘C on the Signature tab copies the signature, as Ctrl+C does
/// in the Python edition.
final class CopyAllTextView: NSTextView {
    var onCopyAll: (() -> Void)?

    override func copy(_ sender: Any?) {
        if selectedRange().length == 0 {
            Platform.copy(string)
            onCopyAll?()
        } else {
            super.copy(sender)
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copy(_:)) { return !string.isEmpty }
        return super.validateMenuItem(menuItem)
    }
}

/// The signature preview.
struct SignaturePreview: NSViewRepresentable {
    var text: String
    var font: NSFont
    var onCopyAll: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CopyAllTextView(frame: .zero)
        let scrollView = embedInScrollView(textView)
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = font
        textView.string = text
        textView.onCopyAll = onCopyAll
        // Take keyboard focus when the tab is shown, so ⌘C copies at once.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 400, height: 300))
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CopyAllTextView else { return }
        textView.onCopyAll = onCopyAll
        if textView.font != font { textView.font = font }
        if textView.string != text {
            textView.string = text
            textView.font = font
        }
    }
}

/// An editable plain-text view (native undo, spelling, Find, dictation).
struct PlainTextEditor: NSViewRepresentable {
    var text: String
    /// Changes when the text is replaced as a new document; resets undo.
    var documentID: Int
    var font: NSFont
    var onEdit: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        let scrollView = embedInScrollView(textView)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.delegate = context.coordinator
        textView.font = font
        textView.string = text
        context.coordinator.textView = textView
        context.coordinator.documentID = documentID
        return scrollView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 400, height: 200))
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if textView.font != font {
            textView.font = font
            textView.typingAttributes[.font] = font
        }
        if coordinator.documentID != documentID {
            coordinator.documentID = documentID
            textView.string = text
            textView.undoManager?.removeAllActions()
        } else if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        weak var textView: NSTextView?
        var documentID = 0

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.onEdit(textView.string)
        }
    }
}
