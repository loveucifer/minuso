import SwiftUI

struct PlayerPane: View {
    @ObservedObject var model: LibraryViewModel
    @State private var showingChapters = false

    private var book: BookSnapshot? { model.selectedBook }
    private var playback: PlaybackEngine { model.playback }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            NowPlayingCover(artwork: book?.artwork)

            Spacer(minLength: 18)
            VStack(spacing: 6) {
                Text(book?.title ?? "Choose a book to begin")
                    .font(.system(size: 25, weight: .regular, design: .serif)).tracking(0.3).lineLimit(1).minimumScaleFactor(0.72)
                Text(book?.author ?? "Select an audiobook from your library")
                    .font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary).lineLimit(1)
                Button { showingChapters = true } label: {
                    HStack(spacing: 6) {
                        Text(currentChapterTitle ?? "Chapter list")
                            .lineLimit(1)
                        if let book {
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(playback.chapterIndex + 1) of \(book.chapterPaths.count)")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).disabled(book == nil).help("Choose a chapter")
                if book != nil {
                    Text("\(Int(liveProgress * 100))% complete · \(TimeText.clock(max(0, (book?.duration ?? 0) * (1 - liveProgress)))) left")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 20)
            VStack(spacing: 7) {
                Slider(value: Binding(get: { playback.elapsed }, set: { playback.seek(to: $0) }), in: 0...max(playback.duration, 1), onEditingChanged: { editing in
                    if !editing { playback.finishSeeking() }
                })
                    .tint(Color(red: 0.34, green: 0.61, blue: 0.73)).disabled(book == nil)
                    .accessibilityLabel("Chapter position")
                HStack {
                    Text(TimeText.clock(playback.elapsed))
                    Spacer()
                    Text("−\(TimeText.clock(max(0, playback.duration - playback.elapsed)))")
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)

            HStack(spacing: 25) {
                Button { playback.skip(by: -model.skipBack) } label: { SkipKey(system: "gobackward", text: "\(Int(model.skipBack))") }
                    .help("Skip back \(Int(model.skipBack)) seconds")
                Button { playback.selectChapter(max(0, playback.chapterIndex - 1)) } label: { Image(systemName: "backward.end.fill") }
                    .help("Previous chapter")
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 62, height: 58)
                        .background(LinearGradient(colors: [.white.opacity(0.9), .gray.opacity(0.34)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.78), lineWidth: 1))
                        .shadow(color: .black.opacity(0.17), radius: 6, y: 4)
                }.buttonStyle(.plain).help(playback.isPlaying ? "Pause" : "Play").disabled(book == nil)
                Button { playback.selectChapter(playback.chapterIndex + 1) } label: { Image(systemName: "forward.end.fill") }
                    .help("Next chapter")
                Button { playback.skip(by: model.skipForward) } label: { SkipKey(system: "goforward", text: "\(Int(model.skipForward))") }
                    .help("Skip forward \(Int(model.skipForward)) seconds")
            }
            .font(.system(size: 14, weight: .medium)).buttonStyle(TransportButtonStyle()).padding(.top, 22)

            HStack(spacing: 12) {
                Image(systemName: model.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
                Slider(value: $model.volume, in: 0...1).frame(maxWidth: 140).onChange(of: model.volume) { _, value in playback.setVolume(value) }
                    .accessibilityLabel("Volume")
                Spacer(minLength: 8)
                SpeedControl(rate: playback.rate, setRate: playback.setRate).disabled(book == nil)
            }
            .padding(.top, 17).padding(.bottom, 20)
            .padding(.horizontal, 28)

            if let message = playback.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).padding(.bottom, 8)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.38), lineWidth: 1))
                .padding(12)
        }
        .sheet(isPresented: $showingChapters) {
            ChapterSheet(book: book, current: playback.chapterIndex) { playback.selectChapter($0) }
                .frame(minWidth: 360, minHeight: 300)
        }
        .onChange(of: book?.id) { _, _ in
            if let book { model.play(book, autoplay: false) }
        }
        .onChange(of: playback.isPlaying) { _, isPlaying in
            if isPlaying { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
        }
    }

    private var liveProgress: Double {
        guard let book, book.duration > 0 else { return 0 }
        let completed = book.chapterDurations.prefix(max(0, playback.chapterIndex)).reduce(0, +)
        let estimate = completed + playback.elapsed
        return min(1, max(0, estimate / book.duration))
    }

    private var currentChapterTitle: String? {
        guard let book, book.chapterPaths.indices.contains(playback.chapterIndex) else { return nil }
        return URL(fileURLWithPath: book.chapterPaths[playback.chapterIndex]).deletingPathExtension().lastPathComponent
    }
}

private struct NowPlayingCover: View {
    let artwork: Data?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.82, green: 0.88, blue: 0.92), Color(red: 0.22, green: 0.31, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let artwork, let image = NSImage(data: artwork) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 276, height: 276)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
        .frame(width: 284, height: 284)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .accessibilityLabel("Audiobook cover artwork")
    }
}

private struct SpeedControl: View {
    let rate: Double
    let setRate: (Double) -> Void
    @State private var isPresented = false
    private let presets = [0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: "speedometer").font(.system(size: 11))
                Text(String(format: "%.2gx", rate)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.quaternary.opacity(0.75), in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Playback speed")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 13) {
                Text("Playback Speed").font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 7) {
                    ForEach(presets, id: \.self) { value in
                        Button {
                            setRate(value)
                        } label: {
                            Text(String(format: "%.2gx", value))
                                .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(abs(rate - value) < 0.001 ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                Slider(value: Binding(get: { rate }, set: setRate), in: 0.5...3, step: 0.05)
                    .accessibilityLabel("Fine playback speed")
                HStack {
                    Text("0.50×")
                    Spacer()
                    Text(String(format: "%.2f×", rate)).fontWeight(.semibold)
                    Spacer()
                    Text("3.00×")
                }
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }
            .padding(15).frame(width: 250)
        }
    }
}

private struct SkipKey: View {
    let system: String
    let text: String
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: system).font(.system(size: 15))
            Text(text).font(.system(size: 7, weight: .medium, design: .monospaced))
        }.frame(width: 35, height: 42)
    }
}

private struct TransportButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 42, height: 42)
            .background(LinearGradient(colors: [.white.opacity(0.72), .gray.opacity(0.23)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.58), lineWidth: 1))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.04 : 0.14), radius: configuration.isPressed ? 1 : 4, y: configuration.isPressed ? 1 : 3)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

private struct ChapterSheet: View {
    let book: BookSnapshot?
    let current: Int
    let select: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapters").font(.system(size: 23, design: .serif)).padding(.horizontal, 18).padding(.top, 18)
            List {
                if let book {
                    ForEach(Array(book.chapterPaths.enumerated()), id: \.offset) { index, path in
                        Button {
                            select(index)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent).lineLimit(1)
                                Spacer()
                                Text(TimeText.clock(book.chapterDurations.indices.contains(index) ? book.chapterDurations[index] : 0))
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                if index == current { Image(systemName: "waveform").foregroundStyle(.red) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.listStyle(.plain)
        }
    }
}
