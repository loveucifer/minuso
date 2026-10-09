import Foundation
import SwiftData
import XCTest
@testable import Minuso

final class LibraryLogicTests: XCTestCase {
    func testNaturalSortUsesNumericOrdering() {
        let urls = ["Chapter 10.mp3", "Chapter 2.mp3", "Chapter 1.mp3"].map { URL(fileURLWithPath: "/\($0)") }
        XCTAssertEqual(AudioBookRules.naturallySorted(urls).map(\.lastPathComponent), ["Chapter 1.mp3", "Chapter 2.mp3", "Chapter 10.mp3"])
    }

    func testFolderDetectionFindsDirectAndNestedBooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let direct = root.appendingPathComponent("Standalone", isDirectory: true)
        let nested = root.appendingPathComponent("Author/Series/Book", isDirectory: true)
        try FileManager.default.createDirectory(at: direct, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: direct.appendingPathComponent("Track 1.mp3"))
        try Data().write(to: nested.appendingPathComponent("Chapter 2.m4b"))

        XCTAssertEqual(try AudioBookRules.bookGroups(in: direct).count, 1)
        XCTAssertEqual(try AudioBookRules.bookGroups(in: nested).count, 1)
        XCTAssertEqual(try AudioBookRules.bookGroups(in: root).count, 2)
    }

    func testSmartRewindThresholdsAndDisabledState() {
        XCTAssertEqual(AudioBookRules.smartRewind(pausedFor: 60), 0)
        XCTAssertEqual(AudioBookRules.smartRewind(pausedFor: 61), 2)
        XCTAssertEqual(AudioBookRules.smartRewind(pausedFor: 601), 5)
        XCTAssertEqual(AudioBookRules.smartRewind(pausedFor: 3_601), 10)
        XCTAssertEqual(AudioBookRules.smartRewind(pausedFor: 3_601, enabled: false), 0)
    }

    func testProgressSurvivesFreshDatabaseRead() async throws {
        let schema = Schema([BookRecord.self, LibraryFolderRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let database = LibraryDatabase(modelContainer: container)
        let id = UUID()
        let scanned = ScannedBook(
            id: id, title: "Test Book", author: "Test Author", sourcePath: "/books/test",
            sourceBookmark: nil, chapterPaths: ["/books/test/Chapter 1.mp3"], chapterDurations: [600], artwork: nil, duration: 600
        )

        _ = try await database.add([scanned])
        _ = try await database.addFolders([LibraryFolderInput(path: "/books", bookmark: Data([1, 2, 3]))])
        try await database.saveProgress(bookID: id, chapterIndex: 0, position: 123.5, pausedAt: .now)
        _ = try await database.add([ScannedBook(
            id: id, title: "Updated Book", author: "Test Author", sourcePath: "/books/test",
            sourceBookmark: nil, chapterPaths: ["/books/test/Chapter 1.mp3"], chapterDurations: [600],
            artwork: Data([4, 5, 6]), duration: 600
        )])
        let loaded = try await database.allBooks().first
        let folders = try await database.allFolders()

        XCTAssertEqual(loaded?.title, "Updated Book")
        XCTAssertEqual(loaded?.chapterPosition, 123.5)
        XCTAssertNotNil(loaded?.lastPaused)
        XCTAssertEqual(folders.first?.path, "/books")
    }

    func testBookProgressIncludesCompletedChapters() {
        let book = BookRecord(
            title: "Book", author: "Author", sourcePath: "/book", sourceBookmark: nil,
            chapterPaths: ["/book/1.mp3", "/book/2.mp3"], chapterDurations: [100, 100],
            artwork: nil, duration: 200, chapterIndex: 1, chapterPosition: 25
        )
        XCTAssertEqual(BookSnapshot(record: book).progress, 0.625, accuracy: 0.001)
    }

    func testNowPlayingSnapshotUsesChapterMetadataAndClampsElapsed() throws {
        let book = BookSnapshot(record: BookRecord(
            title: "The Book", author: "An Author", sourcePath: "/book", sourceBookmark: nil,
            chapterPaths: ["/book/Chapter 1.m4b", "/book/Chapter 2.m4b"],
            chapterDurations: [100, 200], artwork: Data([1, 2]), duration: 300
        ))

        let snapshot = try XCTUnwrap(NowPlayingSnapshot.make(
            book: book, chapterIndex: 1, elapsed: 250, duration: 200, rate: 1.5, isPlaying: true
        ))

        XCTAssertEqual(snapshot.title, "The Book")
        XCTAssertEqual(snapshot.artist, "An Author")
        XCTAssertEqual(snapshot.chapterTitle, "Chapter 2")
        XCTAssertEqual(snapshot.elapsed, 200)
        XCTAssertEqual(snapshot.duration, 200)
        XCTAssertEqual(snapshot.playbackRate, 1.5)
        XCTAssertEqual(snapshot.artwork, Data([1, 2]))
    }

    func testNowPlayingSnapshotWithoutBookIsNilAndInvalidChapterIsSafe() throws {
        XCTAssertNil(NowPlayingSnapshot.make(
            book: nil, chapterIndex: 0, elapsed: 0, duration: 0, rate: 1, isPlaying: false
        ))
        let book = BookSnapshot(record: BookRecord(
            title: "The Book", author: "An Author", sourcePath: "/book", sourceBookmark: nil,
            chapterPaths: [], chapterDurations: [], artwork: nil, duration: 0
        ))

        let snapshot = try XCTUnwrap(NowPlayingSnapshot.make(
            book: book, chapterIndex: 4, elapsed: -3, duration: 0, rate: 1, isPlaying: false
        ))

        XCTAssertEqual(snapshot.chapterTitle, "The Book")
        XCTAssertEqual(snapshot.elapsed, 0)
        XCTAssertEqual(snapshot.duration, 0)
        XCTAssertEqual(snapshot.playbackRate, 0)
        XCTAssertNil(snapshot.artwork)
    }

    func testAppIconStylesPointToAllMacOSExports() {
        XCTAssertEqual(AppIconStyle.allCases.map(\.resourceName), [
            "Untitled-macOS-Default-1024x1024@1x",
            "Untitled-macOS-Dark-1024x1024@1x",
            "Untitled-macOS-ClearLight-1024x1024@1x",
            "Untitled-macOS-ClearDark-1024x1024@1x",
            "Untitled-macOS-TintedLight-1024x1024@1x",
            "Untitled-macOS-TintedDark-1024x1024@1x"
        ])
    }

    func testNowPlayingArtworkCacheDoesNotDecodeUnchangedArtworkAgain() {
        var cache = NowPlayingArtworkCache()
        var decodeCount = 0
        let artwork = Data([1, 2, 3])

        _ = cache.artwork(for: artwork) { _ in decodeCount += 1; return nil }
        _ = cache.artwork(for: artwork) { _ in decodeCount += 1; return nil }
        _ = cache.artwork(for: Data([4, 5, 6])) { _ in decodeCount += 1; return nil }

        XCTAssertEqual(decodeCount, 2)
    }
}
