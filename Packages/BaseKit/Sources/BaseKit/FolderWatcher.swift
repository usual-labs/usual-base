import CoreServices
import Foundation

/// Reports changed paths under a folder, using FSEvents. Agents edit the Base from outside the
/// app, so this is how the sidebar and an open document hear about it.
public final class FolderWatcher: @unchecked Sendable {
    private let handler: @Sendable ([String]) -> Void
    private let queue = DispatchQueue(label: "labs.usual.base.folder-watcher")
    private var stream: FSEventStreamRef?

    /// `handler` runs on a background queue with the changed paths, which FSEvents reports with
    /// symbolic links resolved (`/private/var/…`, not `/var/…`).
    public init?(folder: URL, latency: TimeInterval = 0.2, handler: @escaping @Sendable ([String]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.handler(changed)
        }
        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                [folder.path(percentEncoded: false)] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            )
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
