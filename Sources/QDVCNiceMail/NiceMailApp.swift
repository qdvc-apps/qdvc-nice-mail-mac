import AppKit
import SwiftUI

@main
struct NiceMailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // A single main window, like the GTK app.
        Window("QDVC Nice Mail", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear {
                    appDelegate.model = model
                    model.startUp()
                }
        }
        .defaultSize(width: 1040, height: 660)
        // No window title in the toolbar (as in Calendar), leaving room for the
        // tabs and actions. The title still names the window in the Window
        // menu, Mission Control and VoiceOver (docs/HIG.md §2).
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            NiceMailCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // ⌘F jumps to the search field on the Emoji and Phrases tabs (Ctrl+F
        // in the Python edition). Elsewhere it's left alone, so the note body
        // and signature preview keep the standard Find bar.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f",
                  let model = self?.model, model.workspace != nil, model.currentTab.isSearchable,
                  model.activeSheet == nil else { return event }
            return Platform.focusSearchField(in: event.window) ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
