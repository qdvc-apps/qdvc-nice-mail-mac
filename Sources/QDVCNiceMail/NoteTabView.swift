import AppKit
import SwiftUI
import NiceMailCore

/// The Note to Self tab: an address (used as both From and To), a subject and
/// a plain-text body, saved by Send as a self-addressed .eml with a message
/// ref trailer.
struct NoteTabView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.Key.signatureFontFamily) private var fontFamily = ""
    @AppStorage(Prefs.Key.signatureFontSize) private var fontSize = Prefs.defaultFontSize

    var body: some View {
        @Bindable var model = model
        let nsFont = Prefs.signatureFont(family: fontFamily, size: fontSize)
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("From / To:")
                        .gridColumnAlignment(.trailing)
                    TextField("From / To", text: $model.noteAddress,
                              prompt: Text("your.email@example.com"))
                        .textFieldStyle(.roundedBorder)
                        .font(Font(nsFont as CTFont))
                }
                GridRow {
                    Text("Subject:")
                    TextField("Subject", text: $model.noteSubject)
                        .textFieldStyle(.roundedBorder)
                        .font(Font(nsFont as CTFont))
                }
            }
            PlainTextEditor(text: model.noteBody, documentID: model.noteGeneration, font: nsFont) { text in
                model.noteBody = text
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
            NoteCallout(messageRef: model.noteRef)
        }
        .padding(14)
        .onChange(of: model.noteAddress) { model.noteAddressChanged() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.sendNote()
                } label: {
                    Label("Send", systemImage: "square.and.arrow.down")
                }
                .labelStyle(.titleAndIcon)
                .help("Save the note as an .eml file to send to yourself (\u{2318}S)")

                Button {
                    model.newMessageRef()
                } label: {
                    Label("New Ref", systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)
                .help("Make a new message ref for this note (\u{21E7}\u{2318}R)")
            }
        }
    }
}

/// The green callout naming the message ref the note will carry.
struct NoteCallout: View {
    let messageRef: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
            (Text("This note to self will be assigned ") + Text("Message ref. \(messageRef)").bold())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.35)))
    }
}
