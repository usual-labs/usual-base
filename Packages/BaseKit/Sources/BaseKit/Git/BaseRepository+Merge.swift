import Clibgit2
import Foundation

/// Taking in the remote's commits. Local commits are replayed on top of the remote's, so history
/// stays a straight line and each commit keeps its author. When both sides changed the same
/// lines, the remote's version stays at the path and this Mac's version becomes a conflict copy.
extension BaseRepository {
    func integrate(remoteDefault: String?, as identity: GitIdentity, now: Date, into report: inout SyncReport)
        throws
    {
        let local = try branchName()
        let upstream = upstreamBranch(of: local) ?? remoteDefault ?? local
        // An empty remote, or one without this branch yet: the push creates it.
        guard let remote = try trackingID(upstream) else { return }
        let head = try headID()
        if let newHead = try combine(local: head, remote: remote, as: identity, now: now, into: &report) {
            try checkout(newHead, from: head)
            try moveBranch(from: local, to: upstream, at: newHead)
            report.updatedFromRemote = true
        }
        try rememberUpstream(upstream)
    }

    /// Whether the remote lacks commits that the branch has.
    func needsPush() throws -> Bool {
        guard let head = try headID() else { return false }
        guard let tracking = try trackingID(try branchName()) else { return true }
        return try head != tracking && !isDescendant(tracking, of: head)
    }

    /// The commit that holds both sides, or nil if the local branch already has the remote's
    /// commits.
    private func combine(
        local: ObjectID?, remote: ObjectID, as identity: GitIdentity, now: Date, into report: inout SyncReport
    ) throws -> ObjectID? {
        guard let local else { return remote }
        if try local == remote || isDescendant(local, of: remote) { return nil }
        if try isDescendant(remote, of: local) { return remote }

        let localCommits = try commits(in: local, notIn: remote).map(lookupCommit)
        if localCommits.contains(where: { git_commit_parentcount($0.pointer) > 1 }) {
            return try mergeCommit(local: local, remote: remote, as: identity, now: now, into: &report)
        }
        let committer = try identity.signature(at: now)
        var tip = remote
        for commit in localCommits {
            let parentTree =
                git_commit_parentcount(commit.pointer) == 0
                ? nil : try tree(of: make(git_commit_free) { git_commit_parent(&$0, commit.pointer, 0) })
            let tipCommit = try lookupCommit(tip)
            let tipTree = try tree(of: tipCommit)
            let merged = try mergeTrees(
                base: parentTree?.pointer, remote: tipTree.pointer, local: try tree(of: commit).pointer, now: now,
                into: &report)
            if merged == ObjectID(git_tree_id(tipTree.pointer).pointee) { continue }  // already on the remote
            tip = try createCommit(
                tree: merged, parents: [tipCommit], author: git_commit_author(commit.pointer),
                committer: committer.pointer, message: String(cString: git_commit_message(commit.pointer)))
        }
        return tip
    }

    /// For a local history with merges in it, which replaying would flatten.
    private func mergeCommit(
        local: ObjectID, remote: ObjectID, as identity: GitIdentity, now: Date, into report: inout SyncReport
    ) throws -> ObjectID {
        var localRaw = local.raw
        var remoteRaw = remote.raw
        var baseRaw = git_oid()
        let baseCode = git_merge_base(&baseRaw, repo.pointer, &localRaw, &remoteRaw)
        if baseCode != GIT_ENOTFOUND.rawValue { try check(baseCode) }
        let baseTree = baseCode == 0 ? try tree(of: lookupCommit(ObjectID(baseRaw))) : nil
        let localCommit = try lookupCommit(local)
        let remoteCommit = try lookupCommit(remote)
        let merged = try mergeTrees(
            base: baseTree?.pointer, remote: try tree(of: remoteCommit).pointer,
            local: try tree(of: localCommit).pointer, now: now, into: &report)
        let signature = try identity.signature(at: now)
        return try createCommit(
            tree: merged, parents: [localCommit, remoteCommit], author: signature.pointer,
            committer: signature.pointer, message: "Merge changes from \(Self.remoteName)")
    }

    /// Commits reachable from `tip` but not from `excluded`, oldest first.
    private func commits(in tip: ObjectID, notIn excluded: ObjectID) throws -> [ObjectID] {
        let walk = try make(git_revwalk_free) { git_revwalk_new(&$0, repo.pointer) }
        try check(git_revwalk_sorting(walk.pointer, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_REVERSE.rawValue))
        var tipRaw = tip.raw
        var excludedRaw = excluded.raw
        try check(git_revwalk_push(walk.pointer, &tipRaw))
        try check(git_revwalk_hide(walk.pointer, &excludedRaw))
        var ids: [ObjectID] = []
        var raw = git_oid()
        while true {
            let code = git_revwalk_next(&raw, walk.pointer)
            if code == GIT_ITEROVER.rawValue { return ids }
            try check(code)
            ids.append(ObjectID(raw))
        }
    }

    /// Three-way merges two trees. Where both sides changed a file in ways that clash, the
    /// remote's version keeps the path and the local version is added as a conflict copy.
    private func mergeTrees(
        base: OpaquePointer?, remote: OpaquePointer, local: OpaquePointer, now: Date,
        into report: inout SyncReport
    ) throws -> ObjectID {
        var options = git_merge_options()
        try check(git_merge_options_init(&options, UInt32(GIT_MERGE_OPTIONS_VERSION)))
        let index = try make(git_index_free) { git_merge_trees(&$0, repo.pointer, base, remote, local, &options) }
        if git_index_has_conflicts(index.pointer) != 0 {
            report.conflicts += try keepBothSides(in: index.pointer, now: now)
        }
        var out = git_oid()
        try check(git_index_write_tree_to(&out, index.pointer, repo.pointer))
        return ObjectID(out)
    }

    private struct Side {
        let path: String
        let mode: UInt32
        let id: git_oid

        init(_ entry: UnsafePointer<git_index_entry>) {
            path = String(cString: entry.pointee.path)
            mode = entry.pointee.mode
            id = entry.pointee.id
        }
    }

    /// Resolves every conflict in a merge index and returns where the conflict copies went.
    /// A file one side deleted and the other changed is kept, since that's the only version
    /// with the change.
    private func keepBothSides(in index: OpaquePointer, now: Date) throws -> [SyncReport.Conflict] {
        var conflicts: [(ancestor: Side?, remote: Side?, local: Side?)] = []
        do {
            let iterator = try make(git_index_conflict_iterator_free) {
                git_index_conflict_iterator_new(&$0, index)
            }
            var ancestor: UnsafePointer<git_index_entry>?
            var ours: UnsafePointer<git_index_entry>?
            var theirs: UnsafePointer<git_index_entry>?
            while git_index_conflict_next(&ancestor, &ours, &theirs, iterator.pointer) == 0 {
                conflicts.append((ancestor.map(Side.init), ours.map(Side.init), theirs.map(Side.init)))
            }
        }
        var copies: [SyncReport.Conflict] = []
        for conflict in conflicts {
            for path in Set([conflict.ancestor, conflict.remote, conflict.local].compactMap { $0?.path }) {
                try check(git_index_conflict_remove(index, path))
            }
            if let remote = conflict.remote {
                try add(remote, at: remote.path, to: index)
            }
            guard let local = conflict.local else { continue }
            if conflict.remote == nil {
                try add(local, at: local.path, to: index)
            } else {
                let copy = ConflictCopy.path(for: local.path, date: now) {
                    git_index_get_bypath(index, $0, 0) != nil
                }
                try add(local, at: copy, to: index)
                copies.append(SyncReport.Conflict(path: local.path, copy: copy))
            }
        }
        return copies
    }

    private func add(_ side: Side, at path: String, to index: OpaquePointer) throws {
        var entry = git_index_entry()
        entry.mode = side.mode
        entry.id = side.id
        try path.withCString { cPath in
            entry.path = cPath
            try check(git_index_add(index, &entry))
        }
    }

    /// Updates the folder from `current`'s files to `target`'s. Files changed since `current`
    /// was committed are never overwritten: the checkout stops before writing anything.
    private func checkout(_ target: ObjectID, from current: ObjectID?) throws {
        let commit = try lookupCommit(target)
        let baseline = try current.map { try tree(of: lookupCommit($0)) }
        var options = git_checkout_options()
        try check(git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)))
        options.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        options.baseline = baseline?.pointer
        let code = git_checkout_tree(repo.pointer, commit.pointer, &options)
        if code == GIT_ECONFLICT.rawValue { throw SyncError.folderChanged }
        try check(code)
    }

    /// Points the branch at `id`. The first sync of a new Base takes the remote's branch name.
    private func moveBranch(from local: String, to name: String, at id: ObjectID) throws {
        var raw = id.raw
        _ = try make(git_reference_free) {
            git_reference_create(&$0, repo.pointer, "refs/heads/\(name)", &raw, 1, "Usual Base: sync")
        }
        guard local != name else { return }
        try check(git_repository_set_head(repo.pointer, "refs/heads/\(name)"))
        if let old = try? make(git_reference_free, { git_reference_lookup(&$0, repo.pointer, "refs/heads/\(local)") }) {
            try check(git_reference_delete(old.pointer))
        }
    }
}
