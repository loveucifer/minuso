import AppKit
import SwiftUI

struct LibraryPane: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var selectionStyle: String
    let importAction: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Minuso").font(.system(size: 29, weight: .regular, design: .serif)).tracking(1.5)
                Spacer()
                if model.isScanning { ProgressView().controlSize(.small) }
                Button(action: importAction) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered).controlSize(.regular).help("Add audiobooks or folders")
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 15)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search books", text: $model.query).textFieldStyle(.plain)
                    .accessibilityLabel("Search library")
                    .focused($searchFocused)
                Picker("Sort", selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 115)
            }
            .padding(9).background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 18)

            HStack(spacing: 5) {
                ForEach(LibraryFilter.allCases) { filter in
                    Button(filter.rawValue) { model.filter = filter }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(model.filter == filter ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                        .foregroundStyle(model.filter == filter ? .primary : .secondary)
                }
                Spacer()
                Picker("View", selection: $selectionStyle) {
                    Text("Cases").tag("Cases")
                    Text("List").tag("List")
                }.labelsHidden().pickerStyle(.segmented).frame(width: 94)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)

            if let book = model.continueBook, book.id != model.selectedID {
                Button { model.play(book) } label: {
                    HStack(spacing: 11) {
                        CoverArt(data: book.artwork, size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CONTINUE LISTENING").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(.secondary)
                            Text(book.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "play.fill").font(.system(size: 11))
                    }
                    .padding(9).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.primary.opacity(0.07)))
                }
                .buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 12)
            }

            if model.books.isEmpty {
                EmptyLibraryView(isScanning: model.isScanning, importAction: importAction)
            } else if model.visibleBooks.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else if selectionStyle == "Cases" {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 15)], spacing: 18) {
                        ForEach(model.visibleBooks) { book in BookCase(book: book, selected: book.id == model.selectedID, selectAction: {
                            model.selectedID = book.id
                        }, playAction: { model.play(book) })
                        .contextMenu { bookMenu(book) }
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 20)
                }
            } else {
                List(model.visibleBooks, selection: Binding(get: { model.selectedID }, set: { model.selectedID = $0 })) { book in
                    HStack(spacing: 11) {
                        CoverArt(data: book.artwork, size: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(book.author.uppercased()).font(.system(size: 9, design: .monospaced)).tracking(0.5).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(TimeText.clock(book.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3).tag(book.id).contextMenu { bookMenu(book) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }

        }
        .onChange(of: model.focusSearch) { _, shouldFocus in
            if shouldFocus { searchFocused = true }
            model.focusSearch = false
        }
    }

    @ViewBuilder private func bookMenu(_ book: BookSnapshot) -> some View {
        Button("Play") { model.play(book) }
        Button(book.finished ? "Mark as Unfinished" : "Mark as Finished") { model.markFinished(book, finished: !book.finished) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.sourcePath)]) }
    }
}

private struct EmptyLibraryView: View {
    let isScanning: Bool
    let importAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "opticaldisc").font(.system(size: 37, weight: .ultraLight)).foregroundStyle(.secondary)
            Text("Your listening shelf is clear").font(.system(size: 17, weight: .regular, design: .serif))
            Text("Drop audiobook folders here, or add a folder to begin.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(isScanning ? "Scanning…" : "Add Audiobooks") { importAction() }.disabled(isScanning)
                .buttonStyle(.borderedProminent).tint(.primary.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
        .accessibilityElement(children: .contain)
    }
}

private struct BookCase: View {
    let book: BookSnapshot
    let selected: Bool
    let selectAction: () -> Void
    let playAction: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottom) {
                CoverArt(data: book.artwork, size: 108)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.79, contentMode: .fit)
                    .onTapGesture(perform: selectAction)
                if hovering {
                    Button(action: playAction) {
                        Image(systemName: "play.fill").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 40, height: 40)
                            .background(.black.opacity(0.56), in: Circle())
                    }.buttonStyle(.plain).padding(.bottom, 31)
                }
                GeometryReader { geometry in
                    Rectangle().fill(Color.accentColor.opacity(0.86))
                        .frame(width: geometry.size.width * progress, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
                .frame(height: 2)
                .padding(.horizontal, 1)
            }
            .padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor.opacity(0.7) : .white.opacity(hovering ? 0.55 : 0.24), lineWidth: 1))
            .shadow(color: .black.opacity(hovering ? 0.19 : 0.09), radius: hovering ? 12 : 5, y: hovering ? 7 : 3)
            .scaleEffect(hovering ? 1.025 : 1)
            .onHover { hovering = $0 }
            Text(book.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text(book.author).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(book.title), by \(book.author)\(selected ? ", selected" : "")")
    }

    private var progress: CGFloat {
        CGFloat(book.progress)
    }
}

struct CoverArt: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.68, green: 0.77, blue: 0.83), Color(red: 0.20, green: 0.29, blue: 0.38)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform").font(.system(size: size * 0.28, weight: .ultraLight)).foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .frame(width: size, height: size * 1.23)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.28), lineWidth: 0.7))
        .accessibilityHidden(true)
    }
}
