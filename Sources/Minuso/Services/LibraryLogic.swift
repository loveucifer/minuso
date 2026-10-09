import Foundation

enum AudioBookRules {
    static let supportedExtensions: Set<String> = ["m4b", "m4a", "mp3", "aac", "flac", "wav", "aiff", "aif", "opus"]

    static func naturallySorted(_ urls: [URL]) -> [URL] {
        urls.sorted {
            let result = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            return result == .orderedSame ? $0.path < $1.path : result == .orderedAscending
        }
    }

    static func bookGroups(in folder: URL, fileManager: FileManager = .default) throws -> [[URL]] {
        var groups: [[URL]] = []
        func visit(_ directory: URL) throws {
            let children = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            let audio = children.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            if !audio.isEmpty { groups.append(naturallySorted(audio)) }
            for child in children {
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { continue }
                try? visit(child)
            }
        }
        try visit(folder)
        return groups
    }

    static func smartRewind(pausedFor interval: TimeInterval?, enabled: Bool = true) -> TimeInterval {
        guard enabled, let interval, interval > 60 else { return 0 }
        if interval > 3_600 { return 10 }
        if interval > 600 { return 5 }
        return 2
    }
}

enum TimeText {
    static func clock(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let remainder = value % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
