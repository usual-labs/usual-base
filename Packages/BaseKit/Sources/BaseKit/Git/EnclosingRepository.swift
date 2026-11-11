import Clibgit2
import Foundation

/// The git repository a Base's folder sits inside, such as a project's. The Base is a repository of its own
/// there, so the project's commits must never take it in: the project ignores the folder in its own
/// `info/exclude`, which stays on this Mac and changes none of the project's files.
public enum EnclosingRepository {
    /// Makes the repository around `folder` ignore it, unless something already does. Returns that repository's
    /// working tree, or nil when the folder isn't inside one, or the repository can't be read (the sandbox only
    /// opens folders the person chose).
    @discardableResult
    public static func ignore(_ folder: URL) -> URL? {
        guard (try? Libgit2.start()) != nil else { return nil }
        let parent = folder.deletingLastPathComponent().standardizedFileURL
        var pointer: OpaquePointer?
        guard git_repository_open_ext(&pointer, parent.path(percentEncoded: false), 0, nil) == 0, let pointer else {
            return nil
        }
        let repo = Owned(pointer, free: git_repository_free)
        guard let workdir = git_repository_workdir(repo.pointer).map({ String(cString: $0) }) else { return nil }
        let root = URL(filePath: workdir, directoryHint: .isDirectory).resolvingSymlinksInPath()
        let target = folder.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath =
            root.path(percentEncoded: false).hasSuffix("/")
            ? root.path(percentEncoded: false) : root.path(percentEncoded: false) + "/"
        let path = target.path(percentEncoded: false)
        guard path.hasPrefix(rootPath), path.count > rootPath.count else { return nil }
        let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var ignored: Int32 = 0
        if git_ignore_path_is_ignored(&ignored, repo.pointer, relative + "/") == 0, ignored != 0 { return root }
        // The shared git folder holds info/exclude, also for a worktree.
        let common = URL(filePath: String(cString: git_repository_commondir(repo.pointer)), directoryHint: .isDirectory)
        let exclude = common.appending(path: "info/exclude")
        do {
            try FileManager.default.createDirectory(
                at: exclude.deletingLastPathComponent(), withIntermediateDirectories: true)
            var text = (try? String(contentsOf: exclude, encoding: .utf8)) ?? ""
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += "/" + escaped(relative) + "/\n"
            try Data(text.utf8).write(to: exclude)
        } catch {
            return nil
        }
        return root
    }

    /// The path as a gitignore pattern that matches only itself.
    private static func escaped(_ path: String) -> String {
        var result = ""
        for character in path {
            if "\\*?[]!#".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
