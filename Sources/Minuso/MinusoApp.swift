import AppKit
import SwiftUI

@main
struct MinusoApp: App {
    @StateObject private var model = LibraryViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Minuso") {
            ContentView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        if model.playback.isPlaying { model.playback.pause() }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1050, height: 720)
        .commands {
            SidebarCommands()
            MinusoCommands(
                model: model,
                showImporter: { model.showImporter = true },
                focusSearch: { model.focusSearch = true }
            )
        }

        Settings { SettingsView(model: model) }
    }
}
