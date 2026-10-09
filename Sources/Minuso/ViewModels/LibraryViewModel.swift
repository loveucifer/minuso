import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftData

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var books: [BookSnapshot] = []
    @Published private(set) var libraryFolders: [LibraryFolderSnapshot] = []
    @Published var selectedID: UUID?
    @Published var query = ""
    @Published var sort: LibrarySort = .recentlyPlayed
    @Published var filter: LibraryFilter = .all
    @Published var isScanning = false
    @Published var startupError: String?
    @Published var importError: String?
    @Published var showImporter = false
    @Published var focusSearch = false
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "System"
    @Published var appIconStyle = AppIconStyle(rawValue: UserDefaults.standard.string(forKey: "appIconStyle") ?? "defaultIcon") ?? .defaultIcon
    @Published var volume = 0.8
    @Published var skipBack = 15.0
    @Published var skipForward = 30.0

    let playback = PlaybackEngine()
    private let nowPlaying = NowPlayingController()
    private let folderWatcher = FolderWatcher()
    private let database: LibraryDatabase?
    private var activeFolderAccess: [(URL, Bool)] = []
    private var folderRescanTask: Task<Void, Never>?
    private var hasStarted = false
    private var activeBookID: UUID?
    private var nowPlayingCancellables = Set<AnyCancellable>()

    init() {
        do {
            let container = try ModelContainer(for: BookRecord.self, LibraryFolderRecord.self)
            database = LibraryDatabase(modelContainer: container)
        } catch {
            database = nil
            startupError = "Minuso couldn’t open its library database: \(error.localizedDescription)"
        }
        configureNowPlaying()
        applyAppIcon()
    }

    var selectedBook: BookSnapshot? { books.first { $0.id == selectedID } }
    var continueBook: BookSnapshot? {
        books.filter { $0.progress > 0 && !$0.finished }
            .max { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) }
    }

    var visibleBooks: [BookSnapshot] {
        let matching = books.filter { book in
            let matchesText = query.isEmpty || book.title.localizedCaseInsensitiveContains(query) || book.author.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .inProgress: matchesFilter = book.progress > 0 && !book.finished
            case .notStarted: matchesFilter = book.chapterIndex == 0 && book.chapterPosition == 0 && !book.finished
            case .finished: matchesFilter = book.finished
            }
            return matchesText && matchesFilter
        }
        switch sort {
        case .recentlyPlayed: return matching.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .title: return matching.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author: return matching.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        case .dateAdded: return matching.sorted { $0.dateAdded > $1.dateAdded }
        }
    }

    func refresh() async {
        guard let database else { return }
        do {
            books = try await database.allBooks()
            if selectedID == nil {
                selectedID = books.max(by: { ($0.lastPlayed ?? .distantPast) < ($1.lastPlayed ?? .distantPast) })?.id
                    ?? books.first(where: { !$0.finished })?.id
                    ?? books.first?.id
            }
        } catch {
            importError = "Couldn’t read the library: \(error.localizedDescription)"
        }
    }

    func start() async {
        await refresh()
        guard !hasStarted else { return }
        hasStarted = true
        await reloadLibraryFolders()
        if !activeFolderAccess.isEmpty { await scanAndStore(activeFolderAccess.map(\.0)) }
    }

    func addLibraryFolders(_ urls: [URL]) {
        let inputs = folderInputs(from: urls)
        guard !inputs.isEmpty, let database else { return }
        Task {
            do {
                libraryFolders = try await database.addFolders(inputs)
                await reloadLibraryFolders()
                await scanAndStore(activeFolderAccess.map(\.0))
            } catch {
                importError = "Couldn’t add that library folder: \(error.localizedDescription)"
            }
        }
    }

    func removeLibraryFolder(_ folder: LibraryFolderSnapshot) {
        guard let database else { return }
        Task {
            try? await database.removeFolder(id: folder.id)
            await reloadLibraryFolders()
        }
    }

    func rescanLibrary() {
        let folders = activeFolderAccess.map(\.0)
        guard !folders.isEmpty else { return }
        Task { await scanAndStore(folders) }
    }

    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isScanning = true
        importError = nil
        Task {
            let scoped = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
            let directories = scoped.map(\.0).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            defer {
                for (url, didStart) in scoped where didStart { url.stopAccessingSecurityScopedResource() }
            }
            guard let database else { isScanning = false; return }
            do {
                if !directories.isEmpty {
                    _ = try await database.addFolders(folderInputs(from: directories))
                    await reloadLibraryFolders()
                }
                let found = await LibraryScanner.scan(urls: scoped.map(\.0))
                books = try await database.add(found)
                if let first = found.first { selectedID = books.first(where: { $0.sourcePath == first.sourcePath })?.id }
                if found.isEmpty { importError = "No readable audiobook files were found in that selection." }
            } catch {
                importError = "Couldn’t save the imported books: \(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    func play(_ book: BookSnapshot? = nil, autoplay: Bool = true) {
        guard let book = book ?? selectedBook else { return }
        selectedID = book.id
        if activeBookID == book.id {
            if playback.isAtEnd { playback.selectChapter(0) }
            if !playback.isPlaying { playback.play() }
            return
        }
        activeBookID = book.id
        playback.setVolume(volume)
        playback.load(book, autoplay: autoplay) { [weak self] chapter, position, pausedAt in
            guard let self, let database = self.database else { return }
            if let index = self.books.firstIndex(where: { $0.id == book.id }) {
                self.books[index] = self.books[index].updatingProgress(chapterIndex: chapter, position: position, pausedAt: pausedAt)
            }
            Task { try? await database.saveProgress(bookID: book.id, chapterIndex: chapter, position: position, pausedAt: pausedAt) }
        }
        Task { await refresh() }
    }

    func setAppearance(_ value: String) {
        appearance = value
        UserDefaults.standard.set(value, forKey: "appearance")
    }

    func setAppIconStyle(_ style: AppIconStyle) {
        appIconStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "appIconStyle")
        applyAppIcon()
    }

    func adjustVolume(by amount: Double) {
        volume = min(1, max(0, volume + amount))
        playback.setVolume(volume)
    }

    func adjustSpeed(by amount: Double) { playback.setRate(playback.rate + amount) }

    func dismissErrors() {
        startupError = nil
        importError = nil
    }

    func markFinished(_ book: BookSnapshot, finished: Bool) {
        guard let database else { return }
        Task {
            try? await database.markFinished(bookID: book.id, finished: finished)
            await refresh()
        }
    }

    private func reloadLibraryFolders() async {
        guard let database else { return }
        do {
            libraryFolders = try await database.allFolders()
            for (url, started) in activeFolderAccess where started { url.stopAccessingSecurityScopedResource() }
            activeFolderAccess = libraryFolders.map { folder in
                var stale = false
                let resolved = (try? URL(
                    resolvingBookmarkData: folder.bookmark,
                    options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale
                )) ?? URL(fileURLWithPath: folder.path, isDirectory: true)
                if stale, let refreshed = try? resolved.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    Task { try? await database.updateFolderBookmark(id: folder.id, bookmark: refreshed) }
                }
                return (resolved, resolved.startAccessingSecurityScopedResource())
            }
            folderWatcher.start(paths: activeFolderAccess.map { $0.0.path }) { [weak self] in
                Task { @MainActor in self?.scheduleFolderRescan() }
            }
        } catch {
            importError = "Couldn’t load library folders: \(error.localizedDescription)"
        }
    }

    private func folderInputs(from urls: [URL]) -> [LibraryFolderInput] {
        urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) else { return nil }
            return LibraryFolderInput(path: url.path, bookmark: bookmark)
        }
    }

    private func scheduleFolderRescan() {
        folderRescanTask?.cancel()
        folderRescanTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await scanAndStore(activeFolderAccess.map(\.0))
        }
    }

    private func scanAndStore(_ urls: [URL]) async {
        guard !urls.isEmpty, let database else { return }
        isScanning = true
        let found = await LibraryScanner.scan(urls: urls)
        do {
            books = try await database.add(found)
        } catch {
            importError = "Couldn’t update the library: \(error.localizedDescription)"
        }
        isScanning = false
    }

    private func configureNowPlaying() {
        nowPlaying.configure(
            onPlay: { [weak self] in
                guard let self, self.selectedBook != nil else { return false }
                self.play()
                return true
            },
            onPause: { [weak self] in
                guard let self, self.selectedBook != nil else { return false }
                self.playback.pause()
                return true
            },
            onToggle: { [weak self] in
                guard let self, self.selectedBook != nil else { return false }
                self.playback.toggle()
                return true
            },
            onPrevious: { [weak self] in
                guard let self, let book = self.selectedBook,
                      book.chapterPaths.indices.contains(self.playback.chapterIndex - 1) else { return false }
                self.playback.selectChapter(self.playback.chapterIndex - 1)
                return true
            },
            onNext: { [weak self] in
                guard let self, let book = self.selectedBook,
                      book.chapterPaths.indices.contains(self.playback.chapterIndex + 1) else { return false }
                self.playback.selectChapter(self.playback.chapterIndex + 1)
                return true
            },
            onSeek: { [weak self] position in
                guard let self, self.selectedBook != nil else { return false }
                self.playback.seek(to: position)
                self.playback.finishSeeking()
                return true
            }
        )

        Publishers.Merge(
            $selectedID.map { _ in () }.eraseToAnyPublisher(),
            $books.map { _ in () }.eraseToAnyPublisher()
        )
        .merge(with: playback.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.syncNowPlaying() }
        .store(in: &nowPlayingCancellables)
        syncNowPlaying()
    }

    private func syncNowPlaying() {
        nowPlaying.update(NowPlayingSnapshot.make(
            book: selectedBook,
            chapterIndex: playback.chapterIndex,
            elapsed: playback.elapsed,
            duration: playback.duration,
            rate: playback.rate,
            isPlaying: playback.isPlaying
        ))
    }

    private func applyAppIcon() {
        if let image = appIconStyle.image ?? AppIconStyle.defaultIcon.image {
            NSApplication.shared.applicationIconImage = image
        }
    }
}
