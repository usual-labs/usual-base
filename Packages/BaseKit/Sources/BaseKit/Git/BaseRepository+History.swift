import Clibgit2
import Foundation

/// One commit that changed a file: who made it, when, and its message's first line.
public struct FileChange: Sendable, Equatable, Identifiable {
    /// The commit's full hash.
    public let id: String
    public let author: String
    public let email: String
    public let date: Date
    public let summary: String
}

extension BaseRepository {
    /// The commits that changed the file at `path` (relative to the Base, with `/`), newest first.
    /// It follows each commit's first parent, which is the whole history for the straight line sync
    /// keeps, and looks at no more than `searchLimit` commits, so a long history stays quick.
    public func history(of path: String, limit: Int = 50, searchLimit: Int = 2000) throws -> [FileChange] {
        guard try headID() != nil else { return [] }
        let walk = try make(git_revwalk_free) { git_revwalk_new(&$0, repo.pointer) }
        try check(git_revwalk_sorting(walk.pointer, GIT_SORT_TOPOLOGICAL.rawValue | GIT_SORT_TIME.rawValue))
        try check(git_revwalk_simplify_first_parent(walk.pointer))
        try check(git_revwalk_push_head(walk.pointer))

        var changes: [FileChange] = []
        var raw = git_oid()
        var searched = 0
        while changes.count < limit, searched < searchLimit, git_revwalk_next(&raw, walk.pointer) == 0 {
            searched += 1
            let commit = try lookupCommit(ObjectID(raw))
            let parent = try? make(git_commit_free) { git_commit_parent(&$0, commit.pointer, 0) }
            let before = try parent.flatMap { try blobID(at: path, in: tree(of: $0)) }
            let after = try blobID(at: path, in: tree(of: commit))
            guard before != after else { continue }
            changes.append(change(in: commit, id: ObjectID(raw)))
        }
        return changes
    }

    /// The id of the file at `path` in `tree`, or nil when the tree has no such file.
    private func blobID(at path: String, in tree: Owned<OpaquePointer>) throws -> ObjectID? {
        var entry: OpaquePointer?
        let code = git_tree_entry_bypath(&entry, tree.pointer, path)
        if code == GIT_ENOTFOUND.rawValue { return nil }
        try check(code)
        guard let entry else { return nil }
        defer { git_tree_entry_free(entry) }
        return git_tree_entry_id(entry).map { ObjectID($0.pointee) }
    }

    private func change(in commit: Owned<OpaquePointer>, id: ObjectID) -> FileChange {
        let author = git_commit_author(commit.pointer)?.pointee
        return FileChange(
            id: id.description,
            author: author?.name.map { String(cString: $0) } ?? "",
            email: author?.email.map { String(cString: $0) } ?? "",
            date: Date(timeIntervalSince1970: TimeInterval(author?.when.time ?? 0)),
            summary: git_commit_summary(commit.pointer).map { String(cString: $0) } ?? ""
        )
    }
}
