import Foundation
import Testing

@testable import BaseKit

@Suite struct BaseFolderTests {
    private func makeFolder(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "BaseKitTests-\(UUID().uuidString)")
        for (path, content) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    @Test func scanFindsEveryFileAndSkipsHiddenAndDependencyFolders() throws {
        let root = try makeFolder([
            "README.md": "",
            "docs/agents/02-map.md": "",
            "docs/agents/10-later.markdown": "",
            "docs/image.png": "",
            ".git/HEAD.md": "",
            "node_modules/pkg/readme.md": "",
            ".hidden.md": "",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            BaseIndex.scan(root) == [
                "docs/agents/02-map.md", "docs/agents/10-later.markdown", "docs/image.png", "README.md",
            ])
    }

    @Test func onlyMarkdownOpensInTheApp() {
        #expect(BaseIndex.isMarkdown("Notes/Plan.md"))
        #expect(BaseIndex.isMarkdown("Plan.MARKDOWN"))
        #expect(!BaseIndex.isMarkdown("Tax/2025.pdf"))
        #expect(!BaseIndex.isMarkdown("README"))
    }

    @Test func rankPrefersFileNamesAndWordStarts() {
        let paths = ["agents/known-issues.md", "docs/agents/overview.md", "knowledge/index.md", "notes/kick.md"]
        #expect(BaseIndex.rank("ki", in: paths).first == "agents/known-issues.md")
        #expect(BaseIndex.rank("overview", in: paths) == ["docs/agents/overview.md"])
        #expect(BaseIndex.rank("zzz", in: paths).isEmpty)
        #expect(BaseIndex.rank("", in: paths, limit: 2) == Array(paths.prefix(2)))
    }

    @Test func treeGroupsFoldersFirst() {
        let root = FileNode.tree(from: ["b.md", "a/z.md", "a/c/d.md", "C/e.md"])
        #expect(root.children.map(\.name) == ["a", "C", "b.md"])
        let a = root.children[0]
        #expect(a.children.map(\.path) == ["a/c", "a/z.md"])
        #expect(a.children[0].children.map(\.path) == ["a/c/d.md"])
    }

    @Test func saveNeverOverwritesAChangeOnDisk() throws {
        let root = try makeFolder(["note.md": "original"])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "note.md")
        let (_, lastKnown) = try DocumentStore.read(url)

        // Someone else edits the file, then the app saves its own version.
        try Data("agent edit".utf8).write(to: url)
        let date = Date(timeIntervalSince1970: 0)
        let result = try DocumentStore.save(MarkdownFile(text: "my edit"), to: url, lastKnown: lastKnown, now: date)
        guard case .conflict(let onDisk, let copy) = result else {
            Issue.record("expected a conflict, got \(result)")
            return
        }
        #expect(onDisk == Data("agent edit".utf8))
        #expect(try String(contentsOf: url, encoding: .utf8) == "agent edit")
        #expect(try String(contentsOf: copy, encoding: .utf8) == "my edit")
        #expect(copy.lastPathComponent.hasPrefix("note (conflict "))

        // A second conflict in the same minute gets a numbered name.
        #expect(DocumentStore.conflictCopyURL(for: url, date: date).lastPathComponent.hasSuffix(" 2).md"))
    }

    @Test func saveWritesWhenTheDiskIsUnchangedOrGone() throws {
        let root = try makeFolder(["note.md": "original"])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "note.md")
        let (_, lastKnown) = try DocumentStore.read(url)
        #expect(
            try DocumentStore.save(MarkdownFile(text: "edit"), to: url, lastKnown: lastKnown)
                == .saved(Data("edit".utf8)))
        try FileManager.default.removeItem(at: url)
        #expect(
            try DocumentStore.save(MarkdownFile(text: "again"), to: url, lastKnown: Data("edit".utf8))
                == .saved(Data("again".utf8)))
        #expect(try String(contentsOf: url, encoding: .utf8) == "again")
    }
}
