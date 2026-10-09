import AppKit
import Foundation
import MediaPlayer

struct NowPlayingSnapshot: Sendable {
    let title: String
    let artist: String
    let chapterTitle: String
    let elapsed: Double
    let duration: Double
    let playbackRate: Double
    let artwork: Data?

    static func make(
        book: BookSnapshot?, chapterIndex: Int, elapsed: Double,
        duration: Double, rate: Double, isPlaying: Bool
    ) -> NowPlayingSnapshot? {
        guard let book else { return nil }
        let chapterTitle = book.chapterPaths.indices.contains(chapterIndex)
            ? URL(fileURLWithPath: book.chapterPaths[chapterIndex]).deletingPathExtension().lastPathComponent
            : book.title
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        let safeElapsed = elapsed.isFinite ? min(safeDuration, max(0, elapsed)) : 0
        return NowPlayingSnapshot(
            title: book.title,
            artist: book.author,
            chapterTitle: chapterTitle,
            elapsed: safeElapsed,
            duration: safeDuration,
            playbackRate: isPlaying && rate.isFinite ? max(0.5, rate) : 0,
            artwork: book.artwork
        )
    }
}

struct NowPlayingArtworkCache {
    private var data: Data?
    private var cachedArtwork: MPMediaItemArtwork?

    mutating func artwork(for data: Data?, make: (Data) -> MPMediaItemArtwork?) -> MPMediaItemArtwork? {
        guard self.data != data else { return cachedArtwork }
        self.data = data
        cachedArtwork = data.flatMap(make)
        return cachedArtwork
    }
}

@MainActor
final class NowPlayingController {
    private var isConfigured = false
    private var onPlay: (() -> Bool)?
    private var onPause: (() -> Bool)?
    private var onToggle: (() -> Bool)?
    private var onPrevious: (() -> Bool)?
    private var onNext: (() -> Bool)?
    private var onSeek: ((Double) -> Bool)?
    private var artworkCache = NowPlayingArtworkCache()

    func configure(
        onPlay: @escaping () -> Bool,
        onPause: @escaping () -> Bool,
        onToggle: @escaping () -> Bool,
        onPrevious: @escaping () -> Bool,
        onNext: @escaping () -> Bool,
        onSeek: @escaping (Double) -> Bool
    ) {
        self.onPlay = onPlay
        self.onPause = onPause
        self.onToggle = onToggle
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onSeek = onSeek
        guard !isConfigured else { return }
        isConfigured = true

        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Self.result(self?.onPlay?()) }
        commands.pauseCommand.addTarget { [weak self] _ in Self.result(self?.onPause?()) }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Self.result(self?.onToggle?()) }
        commands.previousTrackCommand.addTarget { [weak self] _ in Self.result(self?.onPrevious?()) }
        commands.nextTrackCommand.addTarget { [weak self] _ in Self.result(self?.onNext?()) }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return Self.result(self?.onSeek?(event.positionTime))
        }
    }

    func update(_ snapshot: NowPlayingSnapshot?) {
        guard let snapshot else { clear(); return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(snapshot.title) — \(snapshot.chapterTitle)",
            MPMediaItemPropertyArtist: snapshot.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: snapshot.playbackRate > 0 ? snapshot.playbackRate : 1
        ]
        if let artwork = artworkCache.artwork(for: snapshot.artwork, make: { data in
            guard let image = NSImage(data: data) else { return nil }
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private static func result(_ succeeded: Bool?) -> MPRemoteCommandHandlerStatus {
        succeeded == true ? .success : .commandFailed
    }
}
