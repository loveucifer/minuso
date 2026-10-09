import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var chapterIndex = 0
    @Published private(set) var rate = 1.0
    @Published private(set) var errorMessage: String?

    private let player = AVQueuePlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var chapters: [ChapterInfo] = []
    private var scopedURL: URL?
    private var onProgress: ((Int, Double, Date?) -> Void)?
    private var lastProgressWrite = Date.distantPast

    var isAtEnd: Bool {
        !chapters.isEmpty && chapterIndex == chapters.count - 1 && duration > 0 && elapsed >= duration - 0.25
    }

    init() {
        player.actionAtItemEnd = .advance
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 2), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in self.updateTime(time) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            let endedURL = (notification.object as? AVPlayerItem)?.asset as? AVURLAsset
            let endedPath = endedURL?.url
            Task { @MainActor in self?.advanceChapter(after: endedPath) }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func load(_ book: BookSnapshot, autoplay: Bool = false, progress: @escaping (Int, Double, Date?) -> Void) {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        if let bookmark = book.sourceBookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
               resolved.startAccessingSecurityScopedResource() {
                scopedURL = resolved
            }
        }
        onProgress = progress
        player.pause()
        isPlaying = false
        player.removeAllItems()
        errorMessage = nil
        chapters = book.chapterPaths.enumerated().compactMap { index, path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            let chapterDuration = book.chapterDurations.indices.contains(index) ? book.chapterDurations[index] : 0
            return ChapterInfo(index: index, title: url.deletingPathExtension().lastPathComponent, url: url, duration: chapterDuration)
        }
        guard !chapters.isEmpty else {
            errorMessage = "These audio files are no longer available."
            return
        }
        chapterIndex = min(max(0, book.chapterIndex), chapters.count - 1)
        for chapter in chapters.dropFirst(chapterIndex) {
            let item = AVPlayerItem(url: chapter.url)
            item.audioTimePitchAlgorithm = .timeDomain
            guard player.canInsert(item, after: nil) else { continue }
            player.insert(item, after: nil)
        }
        duration = chapters[chapterIndex].duration
        elapsed = book.chapterPosition
        let rewind = AudioBookRules.smartRewind(pausedFor: book.lastPaused.map { Date.now.timeIntervalSince($0) })
        let position = max(0, book.chapterPosition - rewind)
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) { [weak self] _ in
            guard autoplay else { return }
            Task { @MainActor in self?.play() }
        }
    }

    func play() {
        guard !chapters.isEmpty else { return }
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        persist(pausedAt: nil, force: true)
    }

    func pause() {
        let current = player.currentTime().seconds
        if current.isFinite { elapsed = current }
        player.pause()
        isPlaying = false
        persist(pausedAt: .now, force: true)
    }

    func toggle() { isPlaying ? pause() : play() }

    func seek(to value: Double) {
        let safeValue = min(max(0, value), max(0, duration))
        elapsed = safeValue
        player.seek(to: CMTime(seconds: safeValue, preferredTimescale: 600))
        persist(pausedAt: isPlaying ? nil : .now, force: false)
    }

    func finishSeeking() { persist(pausedAt: isPlaying ? nil : .now, force: true) }

    func setRate(_ value: Double) {
        rate = min(3, max(0.5, value))
        if isPlaying { player.rate = Float(rate) }
    }

    func setVolume(_ value: Double) { player.volume = Float(min(1, max(0, value))) }

    func skip(by seconds: Double) { seek(to: elapsed + seconds) }

    func selectChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        let shouldPlay = isPlaying
        player.pause()
        isPlaying = false
        player.removeAllItems()
        for chapter in chapters.dropFirst(index) {
            let item = AVPlayerItem(url: chapter.url)
            item.audioTimePitchAlgorithm = .timeDomain
            player.insert(item, after: nil)
        }
        chapterIndex = index
        elapsed = 0
        duration = chapters[index].duration
        if shouldPlay { play() }
        else { persist(pausedAt: .now, force: true) }
    }

    private func updateTime(_ time: CMTime) {
        guard time.seconds.isFinite else { return }
        elapsed = time.seconds
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite { duration = itemDuration }
        if let current = player.currentItem, let currentURL = (current.asset as? AVURLAsset)?.url,
           let index = chapters.firstIndex(where: { $0.url == currentURL }) {
            chapterIndex = index
        }
        if isPlaying { persist(pausedAt: nil, force: false) }
    }

    private func advanceChapter(after endedURL: URL?) {
        let endedIndex = endedURL.flatMap { url in chapters.firstIndex(where: { $0.url == url }) } ?? chapterIndex
        guard endedIndex + 1 < chapters.count else {
            chapterIndex = max(0, chapters.count - 1)
            isPlaying = false
            elapsed = duration
            persist(pausedAt: .now, force: true)
            return
        }
        chapterIndex = endedIndex + 1
        elapsed = 0
        persist(pausedAt: isPlaying ? nil : .now, force: true)
    }

    private func persist(pausedAt: Date?, force: Bool) {
        guard force || Date.now.timeIntervalSince(lastProgressWrite) >= 5 else { return }
        lastProgressWrite = .now
        onProgress?(chapterIndex, elapsed, pausedAt)
    }
}
