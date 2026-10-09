import Foundation
import SwiftData

@ModelActor
actor LibraryDatabase {
    func allBooks() throws -> [BookSnapshot] {
        let descriptor = FetchDescriptor<BookRecord>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        return try modelContext.fetch(descriptor).map(BookSnapshot.init)
    }

    func allFolders() throws -> [LibraryFolderSnapshot] {
        let descriptor = FetchDescriptor<LibraryFolderRecord>(sortBy: [SortDescriptor(\.dateAdded)])
        return try modelContext.fetch(descriptor).map(LibraryFolderSnapshot.init)
    }

    func addFolders(_ folders: [LibraryFolderInput]) throws -> [LibraryFolderSnapshot] {
        var paths = Set(try modelContext.fetch(FetchDescriptor<LibraryFolderRecord>()).map(\.path))
        for folder in folders where paths.insert(folder.path).inserted {
            modelContext.insert(LibraryFolderRecord(path: folder.path, bookmark: folder.bookmark))
        }
        try modelContext.save()
        return try allFolders()
    }

    func removeFolder(id: UUID) throws {
        let descriptor = FetchDescriptor<LibraryFolderRecord>(predicate: #Predicate { $0.id == id })
        if let folder = try modelContext.fetch(descriptor).first { modelContext.delete(folder) }
        try modelContext.save()
    }

    func updateFolderBookmark(id: UUID, bookmark: Data) throws {
        let descriptor = FetchDescriptor<LibraryFolderRecord>(predicate: #Predicate { $0.id == id })
        guard let folder = try modelContext.fetch(descriptor).first else { return }
        folder.bookmark = bookmark
        try modelContext.save()
    }

    func add(_ scanned: [ScannedBook]) throws -> [BookSnapshot] {
        let existing = try modelContext.fetch(FetchDescriptor<BookRecord>())
        var booksByPath = Dictionary(existing.map { ($0.sourcePath, $0) }, uniquingKeysWith: { first, _ in first })
        for scannedBook in scanned {
            if let book = booksByPath[scannedBook.sourcePath] {
                let currentChapterPath = book.chapterPaths.indices.contains(book.chapterIndex) ? book.chapterPaths[book.chapterIndex] : nil
                book.title = scannedBook.title
                book.author = scannedBook.author
                book.sourceBookmark = scannedBook.sourceBookmark
                book.chapterPaths = scannedBook.chapterPaths
                book.chapterDurations = scannedBook.chapterDurations
                book.artwork = scannedBook.artwork
                book.duration = scannedBook.duration
                if let currentChapterPath, let newIndex = scannedBook.chapterPaths.firstIndex(of: currentChapterPath) {
                    book.chapterIndex = newIndex
                } else if currentChapterPath != nil {
                    book.chapterIndex = 0
                    book.chapterPosition = 0
                    book.lastPaused = nil
                }
            } else {
                let record = BookRecord(
                    id: scannedBook.id, title: scannedBook.title, author: scannedBook.author, sourcePath: scannedBook.sourcePath,
                    sourceBookmark: scannedBook.sourceBookmark, chapterPaths: scannedBook.chapterPaths, chapterDurations: scannedBook.chapterDurations,
                    artwork: scannedBook.artwork, duration: scannedBook.duration
                )
                modelContext.insert(record)
                booksByPath[scannedBook.sourcePath] = record
            }
        }
        try modelContext.save()
        return try allBooks()
    }

    func saveProgress(bookID: UUID, chapterIndex: Int, position: Double, pausedAt: Date?) throws {
        let descriptor = FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == bookID })
        guard let book = try modelContext.fetch(descriptor).first else { return }
        book.chapterIndex = chapterIndex
        book.chapterPosition = max(0, position)
        book.lastPlayed = .now
        book.lastPaused = pausedAt
        book.finished = false
        try modelContext.save()
    }

    func markFinished(bookID: UUID, finished: Bool) throws {
        let descriptor = FetchDescriptor<BookRecord>(predicate: #Predicate { $0.id == bookID })
        guard let book = try modelContext.fetch(descriptor).first else { return }
        book.finished = finished
        if finished { book.chapterPosition = book.duration }
        else { book.chapterIndex = 0; book.chapterPosition = 0 }
        try modelContext.save()
    }
}
