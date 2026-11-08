import Clibgit2
import Foundation

/// Who the app's commits are by.
public struct GitIdentity: Sendable, Equatable {
    public var name: String
    public var email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
}

/// HTTPS credentials: a token as the password. Some hosts ignore the user name.
public struct GitCredentials: Sendable, Equatable {
    public var username: String
    public var token: String

    public init(username: String, token: String) {
        self.username = username
        self.token = token
    }
}

/// What one sync did.
public struct SyncReport: Sendable, Equatable {
    /// Changes in the folder went into a new commit.
    public var committed = false
    /// Files in the folder changed to take in the remote's commits.
    public var updatedFromRemote = false
    public var pushed = false
    /// Files where this Mac's change clashed with the remote's. The remote's version kept the
    /// path and this Mac's version went to a conflict copy.
    public var conflicts: [Conflict] = []

    public init() {}

    /// Paths relative to the folder.
    public struct Conflict: Sendable, Equatable {
        public let path: String
        public let copy: String
    }
}

public enum SyncError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The remote wants credentials, and none were given or it refused them.
    case authenticationFailed
    /// The remote couldn't be reached, or answered with an error.
    case unreachable(String)
    /// A file changed while the sync was updating the folder. Nothing was lost; sync again.
    case folderChanged
    /// The remote kept refusing the push.
    case pushRejected(String)
    /// HEAD doesn't point at a branch, so there's nothing to sync.
    case notOnBranch
    case failed(String)

    public var description: String {
        switch self {
        case .authenticationFailed: "The remote didn’t accept the credentials."
        case .unreachable(let message): "Couldn’t reach the remote: \(message)"
        case .folderChanged: "Files changed during the sync."
        case .pushRejected(let message): "The remote refused the changes: \(message)"
        case .notOnBranch: "The folder’s repository isn’t on a branch."
        case .failed(let message): message
        }
    }
}

/// A Base folder that is also a git working tree, synced with its `origin` remote.
///
/// The `.git` folder sits inside the Base like in any clone, so agents on this Mac can read the
/// history and other git tools keep working. Not thread-safe: use an instance from one thread at
/// a time. Every call blocks, network calls included.
public final class BaseRepository {
    public let folder: URL
    let repo: Owned<OpaquePointer>
    static let remoteName = "origin"
    private static let syncKey = "usualbase.sync"

    private init(folder: URL, repo: Owned<OpaquePointer>) {
        self.folder = folder
        self.repo = repo
        // Finder's folder settings never belong in history.
        git_ignore_add_rule(repo.pointer, ".DS_Store\n")
    }

    /// Opens the repository whose working tree is exactly `folder`, or returns nil if there
    /// isn't one. A repository in a parent folder doesn't count.
    public static func open(_ folder: URL) throws -> BaseRepository? {
        try Libgit2.start()
        var pointer: OpaquePointer?
        let code = git_repository_open_ext(
            &pointer, folder.path(percentEncoded: false), GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil)
        if code == GIT_ENOTFOUND.rawValue { return nil }
        try check(code)
        guard let pointer else { return nil }
        let repo = Owned(pointer, free: git_repository_free)
        guard git_repository_is_bare(pointer) == 0 else { return nil }
        return BaseRepository(folder: folder, repo: repo)
    }

    /// Turns sync on for `folder` with `remoteURL` as `origin`, creating the repository if the
    /// folder isn't one yet. An existing repository keeps its history.
    public static func connect(_ folder: URL, to remoteURL: String) throws -> BaseRepository {
        let base = try open(folder) ?? create(folder)
        try base.setRemoteURL(remoteURL)
        try base.setSyncEnabled(true)
        return base
    }

    private static func create(_ folder: URL) throws -> BaseRepository {
        try Libgit2.start()
        var options = git_repository_init_options()
        try check(git_repository_init_options_init(&options, UInt32(GIT_REPOSITORY_INIT_OPTIONS_VERSION)))
        options.flags = GIT_REPOSITORY_INIT_MKPATH.rawValue
        let repo = try "main".withCString { branch in
            options.initial_head = branch
            return try make(git_repository_free) {
                git_repository_init_ext(&$0, folder.path(percentEncoded: false), &options)
            }
        }
        return BaseRepository(folder: folder, repo: repo)
    }

    // MARK: - Settings in the repository's config

    public var remoteURL: String? {
        guard let remote = try? lookupOrigin() else { return nil }
        return git_remote_url(remote.pointer).map { String(cString: $0) }
    }

    public func setRemoteURL(_ url: String) throws {
        if (try? lookupOrigin()) == nil {
            _ = try make(git_remote_free) { git_remote_create(&$0, repo.pointer, Self.remoteName, url) }
        } else {
            try check(git_remote_set_url(repo.pointer, Self.remoteName, url))
        }
    }

    /// Whether the app syncs this Base. It's stored in the repository, so a clone you manage by
    /// hand never starts syncing on its own.
    public var isSyncEnabled: Bool {
        guard let config = try? make(git_config_free, { git_repository_config(&$0, repo.pointer) }) else {
            return false
        }
        var value: Int32 = 0
        return git_config_get_bool(&value, config.pointer, Self.syncKey) == 0 && value != 0
    }

    public func setSyncEnabled(_ enabled: Bool) throws {
        try withLocalConfig { try check(git_config_set_bool($0, Self.syncKey, enabled ? 1 : 0)) }
    }

    /// `user.name` and `user.email` from the repository's own config, if both are set.
    public var configuredIdentity: GitIdentity? {
        guard let config = try? make(git_config_free, { git_repository_config(&$0, repo.pointer) }) else {
            return nil
        }
        guard let name = configString(config.pointer, "user.name"),
            let email = configString(config.pointer, "user.email")
        else { return nil }
        return GitIdentity(name: name, email: email)
    }

    private func withLocalConfig(_ body: (OpaquePointer) throws -> Void) throws {
        let config = try make(git_config_free) { git_repository_config(&$0, repo.pointer) }
        let local = try make(git_config_free) {
            git_config_open_level(&$0, config.pointer, GIT_CONFIG_LEVEL_LOCAL)
        }
        try body(local.pointer)
    }

    private func configString(_ config: OpaquePointer, _ name: String) -> String? {
        var buffer = git_buf()
        defer { git_buf_dispose(&buffer) }
        guard git_config_get_string_buf(&buffer, config, name) == 0, let pointer = buffer.ptr else { return nil }
        return String(cString: pointer)
    }

    /// Records `branch` as tracking the same branch on `origin`, as `git push -u` would.
    func rememberUpstream(_ branch: String) throws {
        try withLocalConfig { config in
            try check(git_config_set_string(config, "branch.\(branch).remote", Self.remoteName))
            try check(git_config_set_string(config, "branch.\(branch).merge", "refs/heads/\(branch)"))
        }
    }

    func upstreamBranch(of branch: String) -> String? {
        guard let config = try? make(git_config_free, { git_repository_config(&$0, repo.pointer) }),
            let merge = configString(config.pointer, "branch.\(branch).merge"), merge.hasPrefix("refs/heads/")
        else { return nil }
        return String(merge.dropFirst("refs/heads/".count))
    }

    // MARK: - Syncing

    /// Commits the folder's changes, takes in the remote's commits and pushes.
    ///
    /// With `fetch` false the remote is only contacted if there's something to push, and only
    /// fetched from if the push is refused. That publishes local edits cheaply.
    public func sync(
        as identity: GitIdentity,
        credentials: GitCredentials?,
        fetch: Bool = true,
        now: Date = .now
    ) throws -> SyncReport {
        var report = SyncReport()
        do {
            report.committed = try commitChanges(as: identity, now: now)
            var mustFetch = fetch
            var lastRefusal = ""
            for _ in 0..<3 {
                if mustFetch {
                    let remoteDefault = try fetchOrigin(credentials)
                    try integrate(remoteDefault: remoteDefault, as: identity, now: now, into: &report)
                }
                guard try needsPush() else { return report }
                guard let refusal = try push(credentials) else {
                    report.pushed = true
                    return report
                }
                lastRefusal = refusal
                mustFetch = true
            }
            throw SyncError.pushRejected(lastRefusal)
        } catch let error as GitError {
            throw error.isNetwork ? SyncError.unreachable(error.message) : SyncError.failed(error.message)
        }
    }

    /// Commits every change in the folder, if there is one. Returns whether it committed.
    @discardableResult
    public func commitChanges(as identity: GitIdentity, now: Date = .now) throws -> Bool {
        let index = try make(git_index_free) { git_repository_index(&$0, repo.pointer) }
        try check(git_index_read(index.pointer, 0))
        try check(git_index_add_all(index.pointer, nil, GIT_INDEX_ADD_DEFAULT.rawValue, nil, nil))
        try check(git_index_update_all(index.pointer, nil, nil, nil))
        try check(git_index_write(index.pointer))
        var treeRaw = git_oid()
        try check(git_index_write_tree(&treeRaw, index.pointer))
        let tree = ObjectID(treeRaw)

        let head = try headID().map(lookupCommit)
        let headTree = head.map { ObjectID(git_commit_tree_id($0.pointer).pointee) }
        if headTree == tree { return false }
        if head == nil, git_tree_entrycount(try lookupTree(tree).pointer) == 0 { return false }

        let message = try describeChanges(from: headTree, to: tree)
        let signature = try identity.signature(at: now)
        _ = try createCommit(
            tree: tree, parents: head.map { [$0] } ?? [], author: signature.pointer, committer: signature.pointer,
            message: message, updateRef: "HEAD")
        return true
    }

    /// "Update notes.md", "Add …", "Delete …", "Rename … to …", or "Add 3 files" and the like.
    private func describeChanges(from old: ObjectID?, to new: ObjectID) throws -> String {
        let oldTree = try old.map(lookupTree)
        let newTree = try lookupTree(new)
        let diff = try make(git_diff_free) {
            git_diff_tree_to_tree(&$0, repo.pointer, oldTree?.pointer, newTree.pointer, nil)
        }
        try check(git_diff_find_similar(diff.pointer, nil))
        let deltas = (0..<git_diff_num_deltas(diff.pointer)).compactMap {
            git_diff_get_delta(diff.pointer, $0)?.pointee
        }
        guard deltas.count == 1, let delta = deltas.first else {
            let verb =
                deltas.allSatisfy({ $0.status == GIT_DELTA_ADDED })
                ? "Add" : deltas.allSatisfy({ $0.status == GIT_DELTA_DELETED }) ? "Delete" : "Update"
            return "\(verb) \(deltas.count) files"
        }
        let oldPath = String(cString: delta.old_file.path)
        let newPath = String(cString: delta.new_file.path)
        switch delta.status {
        case GIT_DELTA_ADDED: return "Add \(newPath)"
        case GIT_DELTA_DELETED: return "Delete \(oldPath)"
        case GIT_DELTA_RENAMED: return "Rename \(oldPath) to \(newPath)"
        default: return "Update \(newPath)"
        }
    }

    // MARK: - Refs and objects

    /// The branch HEAD points at, even before its first commit.
    func branchName() throws -> String {
        let head = try make(git_reference_free) { git_reference_lookup(&$0, repo.pointer, "HEAD") }
        guard git_reference_type(head.pointer) == GIT_REFERENCE_SYMBOLIC,
            let target = git_reference_symbolic_target(head.pointer).map({ String(cString: $0) }),
            target.hasPrefix("refs/heads/")
        else { throw SyncError.notOnBranch }
        return String(target.dropFirst("refs/heads/".count))
    }

    func headID() throws -> ObjectID? { try referenceID("HEAD") }

    func trackingID(_ branch: String) throws -> ObjectID? {
        try referenceID("refs/remotes/\(Self.remoteName)/\(branch)")
    }

    private func referenceID(_ name: String) throws -> ObjectID? {
        var raw = git_oid()
        let code = git_reference_name_to_id(&raw, repo.pointer, name)
        if code == GIT_ENOTFOUND.rawValue || code == GIT_EUNBORNBRANCH.rawValue { return nil }
        try check(code)
        return ObjectID(raw)
    }

    func lookupOrigin() throws -> Owned<OpaquePointer> {
        try make(git_remote_free) { git_remote_lookup(&$0, repo.pointer, Self.remoteName) }
    }

    func lookupCommit(_ id: ObjectID) throws -> Owned<OpaquePointer> {
        var raw = id.raw
        return try make(git_commit_free) { git_commit_lookup(&$0, repo.pointer, &raw) }
    }

    func lookupTree(_ id: ObjectID) throws -> Owned<OpaquePointer> {
        var raw = id.raw
        return try make(git_tree_free) { git_tree_lookup(&$0, repo.pointer, &raw) }
    }

    func tree(of commit: Owned<OpaquePointer>) throws -> Owned<OpaquePointer> {
        try make(git_tree_free) { git_commit_tree(&$0, commit.pointer) }
    }

    func isDescendant(_ commit: ObjectID, of ancestor: ObjectID) throws -> Bool {
        var commitRaw = commit.raw
        var ancestorRaw = ancestor.raw
        let result = git_graph_descendant_of(repo.pointer, &commitRaw, &ancestorRaw)
        try check(result)
        return result == 1
    }

    func createCommit(
        tree treeID: ObjectID,
        parents: [Owned<OpaquePointer>],
        author: UnsafePointer<git_signature>,
        committer: UnsafePointer<git_signature>,
        message: String,
        updateRef: String? = nil
    ) throws -> ObjectID {
        let tree = try lookupTree(treeID)
        var parentPointers: [OpaquePointer?] = parents.map(\.pointer)
        var out = git_oid()
        try parentPointers.withUnsafeMutableBufferPointer { buffer in
            let code: Int32
            if let updateRef {
                code = git_commit_create(
                    &out, repo.pointer, updateRef, author, committer, nil, message, tree.pointer, buffer.count,
                    buffer.baseAddress)
            } else {
                code = git_commit_create(
                    &out, repo.pointer, nil, author, committer, nil, message, tree.pointer, buffer.count,
                    buffer.baseAddress)
            }
            try check(code)
        }
        return ObjectID(out)
    }
}
