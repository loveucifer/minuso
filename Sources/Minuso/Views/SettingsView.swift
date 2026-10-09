import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: LibraryViewModel
    @State private var showingFolderPicker = false

    var body: some View {
        Form {
            Section("Library Folders") {
                Text("Minuso plays files in place. It stores folder access, tags, cover thumbnails, and listening progress—not copies of your audiobooks.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if model.libraryFolders.isEmpty {
                    ContentUnavailableView("No library folders", systemImage: "folder", description: Text("Add folders you already use. Minuso won’t create or move audiobook folders."))
                        .frame(minHeight: 115)
                } else {
                    ForEach(model.libraryFolders) { folder in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(URL(fileURLWithPath: folder.path).lastPathComponent).font(.system(size: 12, weight: .medium))
                                Text(folder.path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)]) }
                                .controlSize(.small)
                            Button(role: .destructive) { model.removeLibraryFolder(folder) } label: {
                                Image(systemName: "minus.circle").accessibilityLabel("Remove folder from library")
                            }
                            .buttonStyle(.borderless).help("Stop watching this folder; audio files stay untouched")
                        }
                    }
                }

                HStack {
                    Button("Add Folder…") { showingFolderPicker = true }
                    Button("Rescan") { model.rescanLibrary() }.disabled(model.isScanning || model.libraryFolders.isEmpty)
                    if model.isScanning { ProgressView().controlSize(.small) }
                }
            }

            Section("Appearance") {
                Picker("Shell", selection: Binding(get: { model.appearance }, set: model.setAppearance)) {
                    Text("Follow System").tag("System")
                    Text("Clear").tag("Clear")
                    Text("Smoke").tag("Smoke")
                }
                .pickerStyle(.segmented)
            }

            Section("App Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(AppIconStyle.allCases) { style in
                        Button { model.setAppIconStyle(style) } label: {
                            VStack(spacing: 6) {
                                Group {
                                    if let image = style.image {
                                        Image(nsImage: image).resizable().scaledToFit()
                                    } else {
                                        Image(systemName: "app.fill").resizable().scaledToFit().padding(12)
                                    }
                                }
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(style.title).font(.system(size: 10, weight: .medium))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity).padding(7)
                            .background(model.appIconStyle == style ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.appIconStyle == style ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(style.title) app icon")
                        .accessibilityAddTraits(model.appIconStyle == style ? .isSelected : [])
                    }
                }
            }

            Section("Playback") {
                HStack {
                    Text("Skip Back")
                    Slider(value: $model.skipBack, in: 5...60, step: 5)
                    Text("\(Int(model.skipBack)) sec").font(.system(size: 10, design: .monospaced)).frame(width: 55, alignment: .trailing)
                }
                HStack {
                    Text("Skip Forward")
                    Slider(value: $model.skipForward, in: 5...90, step: 5)
                    Text("\(Int(model.skipForward)) sec").font(.system(size: 10, design: .monospaced)).frame(width: 55, alignment: .trailing)
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 520, height: 650)
        .fileImporter(isPresented: $showingFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.addLibraryFolders(urls)
            case .failure(let error): model.importError = error.localizedDescription
            }
        }
    }
}
