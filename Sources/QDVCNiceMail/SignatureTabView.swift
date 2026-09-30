import AppKit
import SwiftUI
import NiceMailCore

/// The Signature tab: a read-only preview of the assembled signature. ⌘C
/// copies the selection, or the whole signature when nothing is selected.
struct SignatureTabView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.Key.signatureFontFamily) private var fontFamily = ""
    @AppStorage(Prefs.Key.signatureFontSize) private var fontSize = Prefs.defaultFontSize

    var body: some View {
        @Bindable var model = model
        SignaturePreview(text: model.signatureText,
                         font: Prefs.signatureFont(family: fontFamily, size: fontSize)) {
            model.flash("Signature copied")
        }
        .onChange(of: model.profileName) { model.signatureOptionsChanged() }
        .onChange(of: model.includeDisclaimer) { model.signatureOptionsChanged() }
        .onChange(of: model.refOnly) { model.signatureOptionsChanged() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Profile", selection: $model.profileName) {
                    ForEach(model.profileNames, id: \.self) { name in
                        Text(name).tag(Optional(name))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("The profile file (in mailsigs/profiles) that follows the m-dash")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $model.includeDisclaimer) {
                    Label("Disclaimer", systemImage: "text.badge.checkmark")
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
                .help(model.refOnly ? "Not used in Ref Only mode" : "Include the disclaimer")
                .disabled(model.refOnly)

                Toggle(isOn: $model.refOnly) {
                    Label("Ref Only", systemImage: "number")
                }
                .toggleStyle(.button)
                .labelStyle(.titleAndIcon)
                .help("Only the m-dash and the message ref line")

                Button {
                    model.newMessageRef()
                } label: {
                    Label("New Ref", systemImage: "arrow.clockwise")
                }
                .labelStyle(.titleAndIcon)
                .help("Make a new message ref (\u{21E7}\u{2318}R)")

                Button {
                    model.copySignature()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .labelStyle(.titleAndIcon)
                .help("Copy the whole signature (\u{21E7}\u{2318}C)")
            }
        }
    }
}
