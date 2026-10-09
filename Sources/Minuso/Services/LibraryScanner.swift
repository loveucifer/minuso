import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum LibraryScanner {
    static func scan(urls: [URL]) async -> [ScannedBook] {
        var candidates: [([URL], URL)] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if let groups = try? AudioBookRules.bookGroups(in: url) {
                    candidates.append(contentsOf: groups.compactMap { files in
                        guard let first = files.first else { return nil }
                        return (files, first.deletingLastPathComponent())
                    })
                }
            } else if AudioBookRules.supportedExtensions.contains(url.pathExtension.lowercased()) {
                candidates.append(([url], url))
            }
        }

        var result: [ScannedBook] = []
        for (paths, root) in candidates where !paths.isEmpty {
            if let book = await makeBook(from: paths, root: root) { result.append(book) }
        }
        return result
    }

    private static func makeBook(from files: [URL], root: URL) async -> ScannedBook? {
        guard let firstCandidate = files.first else { return nil }
        var readable: [URL] = []
        var duration = 0.0
        var chapterDurations: [Double] = []
        var title: String?
        var hasEmbeddedTitle = false
        var author = "Unknown author"
        var artwork: Data?

        for file in files {
            do {
                let asset = AVURLAsset(url: file)
                guard try await asset.load(.isPlayable) else {
                    NSLog("Minuso skipped non-playable audio at %@", file.path)
                    continue
                }
                readable.append(file)
                let seconds = try? await asset.load(.duration).seconds
                let chapterDuration = seconds?.isFinite == true ? max(0, seconds ?? 0) : 0
                chapterDurations.append(chapterDuration)
                duration += chapterDuration
                if readable.count == 1 { title = file.deletingPathExtension().lastPathComponent }
                if file == firstCandidate || artwork == nil {
                    let metadata = try await asset.load(.commonMetadata)
                    for item in metadata {
                        switch item.commonKey {
                        case .commonKeyTitle:
                            if file == firstCandidate, let value = try await item.load(.stringValue), !value.isEmpty {
                                title = value
                                hasEmbeddedTitle = true
                            }
                        case .commonKeyArtist, .commonKeyAuthor:
                            if file == firstCandidate, let value = try await item.load(.stringValue), !value.isEmpty { author = value }
                        case .commonKeyArtwork:
                            if artwork == nil { artwork = try await item.load(.dataValue) }
                        default:
                            continue
                        }
                    }
                }
            } catch {
                NSLog("Minuso couldn't inspect audio at %@: %@", file.path, error.localizedDescription)
            }
        }

        guard let first = readable.first else { return nil }
        var resolvedTitle = title ?? first.deletingPathExtension().lastPathComponent
        if author == "Unknown author", root.hasDirectoryPath {
            let folder = root.lastPathComponent
            let pieces = folder.components(separatedBy: " - ")
            if pieces.count > 1 {
                author = pieces[0].trimmingCharacters(in: .whitespaces)
                if !hasEmbeddedTitle {
                    resolvedTitle = pieces.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
                }
            } else if !hasEmbeddedTitle, readable.count > 1 {
                resolvedTitle = folder
            }
        }

        let bookmark = try? root.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        let cover = artwork.flatMap(thumbnail) ?? localCover(in: root)
        return ScannedBook(
            id: UUID(), title: resolvedTitle, author: author, sourcePath: root.path,
            sourceBookmark: bookmark, chapterPaths: readable.map(\.path), chapterDurations: chapterDurations,
            artwork: cover, duration: duration
        )
    }

    private static func localCover(in source: URL) -> Data? {
        let folder = source.hasDirectoryPath ? source : source.deletingLastPathComponent()
        for name in ["cover.jpg", "cover.jpeg", "cover.png", "cover.webp", "folder.jpg", "folder.png", "front.jpg", "front.png", "artwork.jpg", "album.jpg"] {
            let url = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), let image = thumbnail(data) else { continue }
            return image
        }
        return nil
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
