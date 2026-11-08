import Foundation

/// The Markdown files in a Base, as relative paths with `/` separators.
public enum BaseIndex {
    public static let markdownExtensions: Set<String> = ["md", "markdown"]
    /// Folders never worth showing in a knowledge base: dependency trees and build output.
    static let skippedFolders: Set<String> = ["node_modules", "DerivedData", ".build"]

    /// Every Markdown file under `root`, skipping hidden files and folders, sorted the way Finder sorts.
    public static func scan(_ root: URL) -> [String] {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator {
            if skippedFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard markdownExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard path.hasPrefix(prefix) else { continue }
            paths.append(String(path.dropFirst(prefix.count)))
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Paths matching `query` as a fuzzy subsequence, best first. Matches in the file name,
    /// at word starts and in runs score higher; shorter paths win ties.
    public static func rank(_ query: String, in paths: [String], limit: Int = 50) -> [String] {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return Array(paths.prefix(limit)) }
        var scored: [(score: Int, path: String)] = []
        for path in paths {
            if let score = score(needle, Array(path.lowercased())) {
                scored.append((score, path))
            }
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.path < $1.path }
        return scored.prefix(limit).map(\.path)
    }

    private static func score(_ needle: [Character], _ haystack: [Character]) -> Int? {
        let nameStart = (haystack.lastIndex(of: "/") ?? -1) + 1
        var score = 0
        var next = 0
        var previousMatch = -2
        for (index, character) in haystack.enumerated() where next < needle.count && character == needle[next] {
            score += 1
            if index == previousMatch + 1 { score += 4 }
            if index == 0 || "/-_ .".contains(haystack[index - 1]) { score += 6 }
            if index >= nameStart { score += 3 }
            previousMatch = index
            next += 1
        }
        guard next == needle.count else { return nil }
        return score * 20 - haystack.count
    }
}

/// A folder or file in the sidebar. A class, because `NSOutlineView` tells rows apart by identity.
public final class FileNode: @unchecked Sendable {
    public let name: String
    /// Relative to the Base; empty for the root.
    public let path: String
    public let isFolder: Bool
    /// Fixed once `tree(from:)` returns.
    public private(set) var children: [FileNode] = []

    init(name: String, path: String, isFolder: Bool) {
        self.name = name
        self.path = path
        self.isFolder = isFolder
    }

    /// The folders and files for a list of relative file paths. Only folders that hold Markdown
    /// files appear. Folders come before files; both sort the way Finder sorts.
    public static func tree(from paths: [String]) -> FileNode {
        let root = FileNode(name: "", path: "", isFolder: true)
        var folders: [String: FileNode] = ["": root]
        for path in paths {
            let components = path.split(separator: "/").map(String.init)
            var parent = root
            var parentPath = ""
            for (index, component) in components.enumerated() {
                let childPath = parentPath.isEmpty ? component : parentPath + "/" + component
                if index == components.count - 1 {
                    parent.children.append(FileNode(name: component, path: childPath, isFolder: false))
                } else if let folder = folders[childPath] {
                    parent = folder
                } else {
                    let folder = FileNode(name: component, path: childPath, isFolder: true)
                    parent.children.append(folder)
                    folders[childPath] = folder
                    parent = folder
                }
                parentPath = childPath
            }
        }
        root.sortRecursively()
        return root
    }

    private func sortRecursively() {
        children.sort { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        for child in children where child.isFolder { child.sortRecursively() }
    }
}
