import CoreServices
import Foundation

final class FolderWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var isRunning = false
    private var onChange: (() -> Void)?

    func start(paths: [String], onChange: @escaping () -> Void) {
        stop()
        guard !paths.isEmpty else { return }
        lock.lock()
        self.onChange = onChange
        lock.unlock()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            minusoFolderEventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        ) else {
            clearHandler()
            return
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        if FSEventStreamStart(stream) { isRunning = true }
        else { stop() }
    }

    func stop() {
        guard let stream else { clearHandler(); return }
        if isRunning { FSEventStreamStop(stream) }
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isRunning = false
        clearHandler()
    }

    fileprivate func signalChange() {
        lock.lock()
        let handler = onChange
        lock.unlock()
        handler?()
    }

    private func clearHandler() {
        lock.lock()
        onChange = nil
        lock.unlock()
    }

    deinit { stop() }
}

private let minusoFolderEventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().signalChange()
}
