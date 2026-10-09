import Foundation
import SwiftData

@Model
final class BookRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var sourcePath: String
    var sourceBookmark: Data?
    var chapterPaths: [String]
    var chapterDurations: [Double]
    var artwork: Data?
    var duration: Double
    var chapterIndex: Int
    var chapterPosition: Double
    var lastPlayed: Date?
    var lastPaused: Date?
    var finished: Bool
    var dateAdded: Date

    init(
        id: UUID = UUID(), title: String, author: String, sourcePath: String,
        sourceBookmark: Data?, chapterPaths: [String], chapterDurations: [Double], artwork: Data?, duration: Double,
        chapterIndex: Int = 0, chapterPosition: Double = 0, lastPlayed: Date? = nil,
        lastPaused: Date? = nil, finished: Bool = false, dateAdded: Date = .now
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourcePath = sourcePath
        self.sourceBookmark = sourceBookmark
        self.chapterPaths = chapterPaths
        self.chapterDurations = chapterDurations
        self.artwork = artwork
        self.duration = duration
        self.chapterIndex = chapterIndex
        self.chapterPosition = chapterPosition
        self.lastPlayed = lastPlayed
        self.lastPaused = lastPaused
        self.finished = finished
        self.dateAdded = dateAdded
    }
}

@Model
final class LibraryFolderRecord {
    @Attribute(.unique) var id: UUID
    var path: String
    var bookmark: Data
    var dateAdded: Date

    init(id: UUID = UUID(), path: String, bookmark: Data, dateAdded: Date = .now) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.dateAdded = dateAdded
    }
}

struct LibraryFolderSnapshot: Identifiable, Sendable, Hashable {
    let id: UUID
    let path: String
    let bookmark: Data
    let dateAdded: Date

    init(record: LibraryFolderRecord) {
        id = record.id
        path = record.path
        bookmark = record.bookmark
        dateAdded = record.dateAdded
    }
}

struct LibraryFolderInput: Sendable {
    let path: String
    let bookmark: Data
}

struct BookSnapshot: Identifiable, Sendable, Hashable {
    let id: UUID
    let title: String
    let author: String
    let sourcePath: String
    let sourceBookmark: Data?
    let chapterPaths: [String]
    let chapterDurations: [Double]
    let artwork: Data?
    let duration: Double
    let chapterIndex: Int
    let chapterPosition: Double
    let lastPlayed: Date?
    let lastPaused: Date?
    let finished: Bool
    let dateAdded: Date

    init(
        id: UUID, title: String, author: String, sourcePath: String, sourceBookmark: Data?,
        chapterPaths: [String], chapterDurations: [Double], artwork: Data?, duration: Double,
        chapterIndex: Int, chapterPosition: Double, lastPlayed: Date?, lastPaused: Date?,
        finished: Bool, dateAdded: Date
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourcePath = sourcePath
        self.sourceBookmark = sourceBookmark
        self.chapterPaths = chapterPaths
        self.chapterDurations = chapterDurations
        self.artwork = artwork
        self.duration = duration
        self.chapterIndex = chapterIndex
        self.chapterPosition = chapterPosition
        self.lastPlayed = lastPlayed
        self.lastPaused = lastPaused
        self.finished = finished
        self.dateAdded = dateAdded
    }

    init(record: BookRecord) {
        self.init(
            id: record.id, title: record.title, author: record.author, sourcePath: record.sourcePath,
            sourceBookmark: record.sourceBookmark, chapterPaths: record.chapterPaths,
            chapterDurations: record.chapterDurations, artwork: record.artwork, duration: record.duration,
            chapterIndex: record.chapterIndex, chapterPosition: record.chapterPosition,
            lastPlayed: record.lastPlayed, lastPaused: record.lastPaused, finished: record.finished,
            dateAdded: record.dateAdded
        )
    }

    func updatingProgress(chapterIndex: Int, position: Double, pausedAt: Date?) -> BookSnapshot {
        BookSnapshot(
            id: id, title: title, author: author, sourcePath: sourcePath, sourceBookmark: sourceBookmark,
            chapterPaths: chapterPaths, chapterDurations: chapterDurations, artwork: artwork, duration: duration,
            chapterIndex: chapterIndex, chapterPosition: max(0, position), lastPlayed: .now,
            lastPaused: pausedAt, finished: false, dateAdded: dateAdded
        )
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        let completed = chapterDurations.prefix(max(0, chapterIndex)).reduce(0, +)
        let currentDuration = chapterDurations.indices.contains(chapterIndex) ? chapterDurations[chapterIndex] : 0
        return min(1, max(0, (completed + min(chapterPosition, currentDuration > 0 ? currentDuration : chapterPosition)) / duration))
    }
}

struct ScannedBook: Sendable {
    let id: UUID
    let title: String
    let author: String
    let sourcePath: String
    let sourceBookmark: Data?
    let chapterPaths: [String]
    let chapterDurations: [Double]
    let artwork: Data?
    let duration: Double

}

struct ChapterInfo: Identifiable, Sendable {
    let index: Int
    let title: String
    let url: URL
    let duration: Double
    var id: Int { index }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyPlayed = "Recently Played"
    case title = "Title"
    case author = "Author"
    case dateAdded = "Date Added"
    var id: String { rawValue }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All Books"
    case inProgress = "In Progress"
    case notStarted = "Not Started"
    case finished = "Finished"
    var id: String { rawValue }
}
