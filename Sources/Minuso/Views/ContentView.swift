import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: LibraryViewModel
    @State private var selectionStyle = "Cases"

    private var shell: ColorScheme? {
        switch model.appearance {
        case "Clear": return .light
        case "Smoke": return .dark
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            LibraryPane(model: model, selectionStyle: $selectionStyle, importAction: { model.showImporter = true })
                .frame(minWidth: 310, idealWidth: 380, maxWidth: 460)
            Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
            PlayerPane(model: model)
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(colors: [Color.white.opacity(0.20), .clear, Color.black.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Appearance", selection: Binding(get: { model.appearance }, set: model.setAppearance)) {
                        Text("Follow System").tag("System")
                        Text("Clear").tag("Clear")
                        Text("Smoke").tag("Smoke")
                    }
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                }
                .help("Appearance")
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .preferredColorScheme(shell)
        .frame(minWidth: 820, minHeight: 560)
        .fileImporter(
            isPresented: $model.showImporter,
            allowedContentTypes: [.audio, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): model.importURLs(urls)
            case .failure(let error): model.importError = error.localizedDescription
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: acceptDrop)
        .task { await model.start() }
        .alert("Library issue", isPresented: Binding(
            get: { model.startupError != nil || model.importError != nil },
            set: { if !$0 { model.dismissErrors() } }
        )) {
            Button("OK", role: .cancel) { model.dismissErrors() }
        } message: {
            Text(model.startupError ?? model.importError ?? "An unknown error occurred.")
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url else { return }
                DispatchQueue.main.async { model.importURLs([url]) }
            }
        }
        return !providers.isEmpty
    }
}

struct MinusoCommands: Commands {
    @ObservedObject var model: LibraryViewModel
    let showImporter: () -> Void
    let focusSearch: () -> Void

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Audiobooks…", action: showImporter).keyboardShortcut("o", modifiers: [.command])
            Button("Search Library", action: focusSearch).keyboardShortcut("f", modifiers: [.command])
        }
        CommandMenu("Playback") {
            Button(model.playback.isPlaying ? "Pause" : "Play", action: model.playback.toggle).keyboardShortcut(.space, modifiers: [])
            Button("Skip Back \(Int(model.skipBack)) Seconds") { model.playback.skip(by: -model.skipBack) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Skip Forward \(Int(model.skipForward)) Seconds") { model.playback.skip(by: model.skipForward) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Previous Chapter") { model.playback.selectChapter(max(0, model.playback.chapterIndex - 1)) }
                .keyboardShortcut(.leftArrow, modifiers: [.shift])
            Button("Next Chapter") { model.playback.selectChapter(model.playback.chapterIndex + 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.shift])
            Divider()
            Button("Volume Up") { model.adjustVolume(by: 0.05) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Volume Down") { model.adjustVolume(by: -0.05) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("Slower") { model.adjustSpeed(by: -0.05) }.keyboardShortcut("[", modifiers: [])
            Button("Faster") { model.adjustSpeed(by: 0.05) }.keyboardShortcut("]", modifiers: [])
        }
    }
}
