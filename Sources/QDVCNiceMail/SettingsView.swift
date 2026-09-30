import AppKit
import SwiftUI
import NiceMailCore

/// The Settings window (⌘,) — the Mac home of the GTK Preferences dialog.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.Key.skinTone) private var skinTone = SkinTone.none.rawValue
    @AppStorage(Prefs.Key.signatureFontFamily) private var fontFamily = ""
    @AppStorage(Prefs.Key.signatureFontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.Key.reopenLast) private var reopenLast = true

    private let families = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Form {
            Section("Emoji") {
                Picker("Skin tone", selection: $skinTone) {
                    ForEach(SkinTone.allCases) { tone in
                        Text(Emoji(id: "tone", char: "\u{1F44B}", name: "").display(skinTone: tone)
                             + "  " + tone.label)
                            .tag(tone.rawValue)
                    }
                }
            }

            Section {
                Picker("Font", selection: $fontFamily) {
                    Text("Default (monospaced)").tag("")
                    Divider()
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: $fontSize, in: 9...28, step: 1) {
                    Text("Size: \(Int(fontSize)) pt")
                }
                if !fontFamily.isEmpty || fontSize != Prefs.defaultFontSize {
                    Button("Use Default Font") {
                        fontFamily = ""
                        fontSize = Prefs.defaultFontSize
                    }
                }
            } header: {
                Text("Signature and Note to Self")
            } footer: {
                Text("Used by the signature preview and the Note to Self fields. It doesn\u{2019}t change what you copy or save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Workspace") {
                Toggle("Reopen the last workspace at launch", isOn: $reopenLast)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: skinTone) { model.refreshEmojiRows() }
    }
}
