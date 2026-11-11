import BaseKit
import Foundation

/// The git work for one Base. It runs on its own serial queue, so libgit2's blocking calls,
/// network ones included, never hold up the main thread or Swift's shared threads.
actor SyncEngine {
    nonisolated let folder: URL
    private let queue = DispatchSerialQueue(label: "labs.usual.base.sync")
    private var repository: BaseRepository?

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(folder: URL) {
        self.folder = folder
    }

    struct State: Sendable {
        let isEnabled: Bool
        let remoteURL: String?
        let identity: GitIdentity?
    }

    func load() throws -> State {
        repository = try BaseRepository.open(folder)
        guard let repository else { return State(isEnabled: false, remoteURL: nil, identity: nil) }
        return State(
            isEnabled: repository.isSyncEnabled, remoteURL: repository.remoteURL,
            identity: repository.configuredIdentity)
    }

    func connect(to url: String) throws {
        repository = try BaseRepository.connect(folder, to: url)
    }

    func stop() throws {
        try repository?.setSyncEnabled(false)
    }

    /// The commits that changed `path`, or nil when the Base isn't a git repository.
    func history(of path: String) throws -> [FileChange]? {
        // The pane can ask before `load` has run.
        if repository == nil { repository = try BaseRepository.open(folder) }
        return try repository?.history(of: path)
    }

    func sync(as identity: GitIdentity, credentials: GitCredentials?, fetch: Bool) throws -> SyncReport {
        guard let repository else { throw SyncError.failed("This Base isn’t set up to sync.") }
        return try repository.sync(as: identity, credentials: credentials, fetch: fetch)
    }
}
