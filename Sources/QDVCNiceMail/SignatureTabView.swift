import AppKit
import SwiftUI
import NiceMailCore

/// The Signature tab: a read-only preview of the assembled signature, under a
/// slim bar with the Disclaimer and Ref Only checkboxes (like Preview's
/// Markup toolbar). The profile picker, New Ref and Copy are in the toolbar
/// (docs/HIG.md §3). ⌘C copies the selection, or the whole signature when
/// nothing is selected.
struct SignatureTabView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.Key.signatureFontFamily) private var fontFamily = ""
    @AppStorage(Prefs.Key.signatureFontSize) private var fontSize = Prefs.defaultFontSize

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            OptionBar {
                Toggle("Include disclaimer", isOn: $model.includeDisclaimer)
                    .toggleStyle(.checkbox)
                    .disabled(model.refOnly)
                    .help(model.refOnly ? "Not used when Ref only is on"
                                        : "Add the disclaimer from mailsigs/disclaimer.txt")
                Toggle("Ref only", isOn: $model.refOnly)
                    .toggleStyle(.checkbox)
                    .help("Only the m-dash and the message ref line")
            }
            SignaturePreview(text: model.signatureText,
                             font: Prefs.signatureFont(family: fontFamily, size: fontSize)) {
                model.noteCopied()
            }
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
                NewRefToolbarButton(help: "New message ref (\u{2318}R)")
                CopyToolbarButton(help: "Copy the whole signature (\u{21E7}\u{2318}C)") {
                    model.copySignature()
                }
            }
        }
    }
}
