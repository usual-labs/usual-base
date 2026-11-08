import AppKit
import BaseKit
import Observation

/// Keeps the open Base in step with its git remote. Local changes are published once the
/// folder has been quiet for a few seconds; the remote is checked every minute and whenever
/// the app comes to the front.
@MainActor @Observable
final class SyncController {
    enum Status: Equatable {
        /// This Base isn't set up to sync.
        case off
        case syncing
        case synced(Date)
        /// The remote couldn't be reached. Syncing carries on when it can.
        case offline(String)
        /// The remote refused the credentials. Automatic syncs wait for new ones.
        case needsCredentials
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var remoteURL: String?
    /// Clashes from this session's syncs, newest first.
    private(set) var conflicts: [SyncReport.Conflict] = []
    var isSetupShown = false

    /// Runs before each sync, so the open document's edits are on disk.
    @ObservationIgnored var willSync: () -> Void = {}
    @ObservationIgnored var didFindConflicts: ([SyncReport.Conflict]) -> Void = { _ in }

    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var credentials: GitCredentials?
    @ObservationIgnored private var running: Task<Void, Never>?
    /// A sync asked for while another ran: nil for none, true if it should fetch.
    @ObservationIgnored private var queuedFetch: Bool?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastFetch = Date.distantPast
    @ObservationIgnored private var repositoryIdentity: GitIdentity?

    /// How long the folder must be quiet before local changes are committed and pushed. Hosted
    /// remotes bill each push, so typing shouldn't push on every pause.
    static let settleDelay: Duration = .seconds(5)
    static let pollInterval: Duration = .seconds(60)

    private var isAutomatic: Bool {
        switch status {
        case .off, .needsCredentials: false
        default: true
        }
    }

    // MARK: - Opening and closing a Base

    func open(_ folder: URL) {
        close()
        let engine = SyncEngine(folder: folder)
        self.engine = engine
        Task {
            let state = try? await engine.load()
            guard self.engine === engine, let state else { return }
            remoteURL = state.remoteURL
            repositoryIdentity = state.identity
            if state.isEnabled { start() }
        }
    }

    func close() {
        engine = nil
        stopTimers()
        status = .off
        remoteURL = nil
        credentials = nil
        repositoryIdentity = nil
        conflicts = []
    }

    private func start() {
        credentials = remoteURL.flatMap(CredentialStore.credentials(for:))
        startPolling()
        request(fetch: true)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                if isAutomatic { request(fetch: true) }
            }
        }
    }

    private func stopTimers() {
        pollTask?.cancel()
        settleTask?.cancel()
        pollTask = nil
        settleTask = nil
    }

    // MARK: - When to sync

    /// Files in the Base changed (not inside `.git`).
    func filesChanged() {
        guard isAutomatic else { return }
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            request(fetch: false)
        }
    }

    func appBecameActive() {
        guard isAutomatic, Date.now.timeIntervalSince(lastFetch) > 20 else { return }
        request(fetch: true)
    }

    func syncNow() {
        guard engine != nil, remoteURL != nil, status != .off else { return }
        request(fetch: true)
    }

    private func request(fetch: Bool) {
        guard let engine else { return }
        guard running == nil else {
            queuedFetch = (queuedFetch ?? false) || fetch
            return
        }
        willSync()
        status = .syncing
        let identity = identity
        let credentials = credentials
        running = Task {
            let result: Result<SyncReport, Error>
            do {
                result = .success(try await engine.sync(as: identity, credentials: credentials, fetch: fetch))
            } catch {
                result = .failure(error)
            }
            guard self.engine === engine else { return }
            finish(result, fetched: fetch)
        }
    }

    private func finish(_ result: Result<SyncReport, Error>, fetched: Bool) {
        running = nil
        switch result {
        case .success(let report):
            if fetched { lastFetch = .now }
            status = .synced(.now)
            if !report.conflicts.isEmpty {
                conflicts.insert(contentsOf: report.conflicts, at: 0)
                didFindConflicts(report.conflicts)
            }
        case .failure(SyncError.authenticationFailed):
            status = .needsCredentials
            queuedFetch = nil
        case .failure(SyncError.unreachable(let message)):
            status = .offline(message)
        case .failure(SyncError.folderChanged):
            // Something wrote while the sync updated the folder; nothing was touched. Wait for
            // the folder to settle and go again.
            status = .syncing
            filesChanged()
        case .failure(let error):
            status = .failed(String(describing: error))
        }
        if let next = queuedFetch {
            queuedFetch = nil
            request(fetch: next)
        }
    }

    // MARK: - Setting up

    /// The commit author for this Mac's changes: what the setup sheet saved, else the
    /// repository's `user.name` and `user.email`, else `user@host` as git itself would use.
    var identity: GitIdentity {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "authorName"), let email = defaults.string(forKey: "authorEmail"),
            !name.isEmpty, !email.isEmpty
        {
            return GitIdentity(name: name, email: email)
        }
        return repositoryIdentity
            ?? GitIdentity(name: NSFullUserName(), email: "\(NSUserName())@\(ProcessInfo.processInfo.hostName)")
    }

    static func saveIdentity(_ identity: GitIdentity) {
        UserDefaults.standard.set(identity.name, forKey: "authorName")
        UserDefaults.standard.set(identity.email, forKey: "authorEmail")
    }

    func savedCredentials(for url: String) -> GitCredentials? {
        CredentialStore.credentials(for: url)
    }

    /// Points the Base at `url`, stores the credentials and runs the first sync. Returns a
    /// message for the setup sheet if something went wrong.
    func connect(to address: RemoteAddress, credentials newCredentials: GitCredentials?, as identity: GitIdentity)
        async -> String?
    {
        guard let engine else { return "Open a Base first." }
        await running?.value
        stopTimers()
        let credentials = newCredentials ?? CredentialStore.credentials(for: address.url)
        do {
            if let newCredentials { try CredentialStore.save(newCredentials, for: address.url) }
            Self.saveIdentity(identity)
            try await engine.connect(to: address.url)
        } catch {
            return "Couldn’t set up sync: \(error)"
        }
        remoteURL = address.url
        self.credentials = credentials
        status = .syncing
        willSync()
        do {
            let report = try await engine.sync(as: identity, credentials: credentials, fetch: true)
            finish(.success(report), fetched: true)
            startPolling()
            return nil
        } catch SyncError.authenticationFailed {
            status = .needsCredentials
            return credentials == nil
                ? "The repository needs a token. Paste one that can read and push to it."
                : "The repository didn’t accept the token. Check that it’s right and can push."
        } catch {
            // Sync is set up; it keeps trying in the background.
            finish(.failure(error), fetched: true)
            startPolling()
            return String(describing: error)
        }
    }

    /// Turns sync off for this Base and forgets its token. The folder and its history stay.
    func stopSyncing() async {
        guard let engine else { return }
        await running?.value
        try? await engine.stop()
        if let remoteURL { CredentialStore.delete(for: remoteURL) }
        stopTimers()
        credentials = nil
        status = .off
    }
}
