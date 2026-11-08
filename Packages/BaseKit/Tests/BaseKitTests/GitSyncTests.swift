import Foundation
import Testing

@testable import BaseKit

/// Two Bases syncing through a bare repository on disk, with the git command line as a
/// second opinion on what landed in the remote.
@Suite struct GitSyncTests {
    let mac = GitIdentity(name: "Mac", email: "mac@example.com")
    let agent = GitIdentity(name: "Agent", email: "agent@example.com")
    let sandbox = try! Sandbox()

    @Test func publishesAFolderToAnEmptyRemoteByteForByte() throws {
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("# Notes\r\n\r\n- one\r\n".utf8)
        try sandbox.write(original, "a/notes.md")
        try sandbox.write("finder junk", "a/.DS_Store")
        let a = try sandbox.connect("a")
        let published = try a.sync(as: mac, credentials: nil)
        #expect(published.committed && published.pushed)

        let b = try sandbox.connect("b")
        let cloned = try b.sync(as: agent, credentials: nil)
        #expect(cloned.updatedFromRemote && !cloned.committed && !cloned.pushed)
        #expect(try sandbox.data("b/notes.md") == original)
        #expect(!sandbox.exists("b/.DS_Store"))
        #expect(try sandbox.git("log", "--format=%an %s") == "Mac Add notes.md")
    }

    @Test func describesEachCommit() throws {
        try sandbox.write("1", "a/one.md")
        try sandbox.write("2", "a/two.md")
        let a = try sandbox.connect("a")
        _ = try a.sync(as: mac, credentials: nil)
        try FileManager.default.moveItem(at: sandbox.url("a/two.md"), to: sandbox.url("a/three.md"))
        _ = try a.sync(as: mac, credentials: nil)
        try sandbox.write("one", "a/one.md")
        _ = try a.sync(as: mac, credentials: nil)
        #expect(try sandbox.git("log", "--format=%s") == "Update one.md\nRename two.md to three.md\nAdd 2 files")
    }

    @Test func doesNothingWhenNothingChanged() throws {
        try sandbox.write("hello", "a/notes.md")
        let a = try sandbox.connect("a")
        _ = try a.sync(as: mac, credentials: nil)
        #expect(try a.sync(as: mac, credentials: nil) == SyncReport())
    }

    @Test func bringsInEditsFromTheRemote() throws {
        let (a, b) = try twoBases(["notes.md": "one\n"])
        try sandbox.write("one\ntwo\n", "a/notes.md")
        _ = try a.sync(as: mac, credentials: nil)
        let report = try b.sync(as: agent, credentials: nil)
        #expect(report.updatedFromRemote && !report.committed)
        #expect(try sandbox.text("b/notes.md") == "one\ntwo\n")
    }

    @Test func mergesEditsToDifferentLinesAndKeepsHistoryStraight() throws {
        let (a, b) = try twoBases(["notes.md": "1\n2\n3\n4\n5\n"])
        try sandbox.write("1 mac\n2\n3\n4\n5\n", "a/notes.md")
        try sandbox.write("1\n2\n3\n4\n5 agent\n", "b/notes.md")
        _ = try a.sync(as: mac, credentials: nil)
        let report = try b.sync(as: agent, credentials: nil)
        #expect(report.pushed && report.conflicts.isEmpty)
        #expect(try sandbox.text("b/notes.md") == "1 mac\n2\n3\n4\n5 agent\n")
        _ = try a.sync(as: mac, credentials: nil)
        #expect(try sandbox.text("a/notes.md") == "1 mac\n2\n3\n4\n5 agent\n")
        #expect(try sandbox.git("log", "--merges", "--format=%H").isEmpty)
        #expect(try sandbox.git("log", "-2", "--format=%an") == "Agent\nMac")
    }

    @Test func keepsTheRemoteVersionAndACopyWhenEditsClash() throws {
        let (a, b) = try twoBases(["notes.md": "draft\n"])
        try sandbox.write("mac's version\n", "a/notes.md")
        try sandbox.write("agent's version\n", "b/notes.md")
        _ = try a.sync(as: mac, credentials: nil)
        let report = try b.sync(as: agent, credentials: nil)
        let copy = try #require(report.conflicts.first).copy
        #expect(copy.hasPrefix("notes (conflict ") && copy.hasSuffix(").md"))
        #expect(try sandbox.text("b/notes.md") == "mac's version\n")
        #expect(try sandbox.text("b/" + copy) == "agent's version\n")
        _ = try a.sync(as: mac, credentials: nil)
        #expect(try sandbox.text("a/" + copy) == "agent's version\n")
    }

    @Test func keepsAFileOneSideEditedAndTheOtherDeleted() throws {
        let (a, b) = try twoBases(["notes.md": "draft\n", "other.md": "x\n"])
        try FileManager.default.removeItem(at: sandbox.url("a/notes.md"))
        try sandbox.write("still needed\n", "b/notes.md")
        _ = try a.sync(as: mac, credentials: nil)
        _ = try b.sync(as: agent, credentials: nil)
        #expect(try sandbox.text("b/notes.md") == "still needed\n")
        _ = try a.sync(as: mac, credentials: nil)
        #expect(try sandbox.text("a/notes.md") == "still needed\n")
    }

    @Test func fetchesAndRetriesWhenAPushIsRefused() throws {
        let (a, b) = try twoBases(["notes.md": "x\n"])
        try sandbox.write("from mac\n", "a/mac.md")
        try sandbox.write("from agent\n", "b/agent.md")
        _ = try a.sync(as: mac, credentials: nil)
        let report = try b.sync(as: agent, credentials: nil, fetch: false)
        #expect(report.pushed && report.updatedFromRemote)
        #expect(try sandbox.text("b/mac.md") == "from mac\n")
    }

    @Test func joinsARemoteThatAlreadyHasFiles() throws {
        try sandbox.write("from a\n", "a/shared.md")
        _ = try sandbox.connect("a").sync(as: mac, credentials: nil)
        try sandbox.write("from c\n", "c/shared.md")
        try sandbox.write("only c\n", "c/own.md")
        let report = try sandbox.connect("c").sync(as: agent, credentials: nil)
        let copy = try #require(report.conflicts.first).copy
        #expect(try sandbox.text("c/shared.md") == "from a\n")
        #expect(try sandbox.text("c/" + copy) == "from c\n")
        #expect(try sandbox.git("show", "HEAD:own.md") == "only c")
    }

    @Test func neverOverwritesAFileChangedDuringASync() throws {
        let (a, b) = try twoBases(["notes.md": "draft\n"])
        try sandbox.write("mac's version\n", "a/notes.md")
        _ = try a.sync(as: mac, credentials: nil)
        // The agent's edit lands after the sync committed, just before it updates the folder.
        try sandbox.write("agent's late edit\n", "b/notes.md")
        let remoteDefault = try b.fetchOrigin(nil)
        var report = SyncReport()
        #expect(throws: SyncError.folderChanged) {
            try b.integrate(remoteDefault: remoteDefault, as: agent, now: .now, into: &report)
        }
        #expect(try sandbox.text("b/notes.md") == "agent's late edit\n")
        let retry = try b.sync(as: agent, credentials: nil)
        #expect(retry.conflicts.map(\.path) == ["notes.md"])
    }

    @Test func leavesExistingClonesAloneUntilConnected() throws {
        try FileManager.default.createDirectory(at: sandbox.url("d"), withIntermediateDirectories: true)
        try sandbox.run("git", "init", "-q", sandbox.url("d").path)
        let opened = try #require(try BaseRepository.open(sandbox.url("d")))
        #expect(!opened.isSyncEnabled)
        #expect(try BaseRepository.open(sandbox.url("d/sub")) == nil)
        #expect(try BaseRepository.connect(sandbox.url("d"), to: sandbox.remote).isSyncEnabled)
    }

    /// Two Bases on the same remote, both holding `files`.
    private func twoBases(_ files: [String: String]) throws -> (BaseRepository, BaseRepository) {
        for (path, text) in files { try sandbox.write(text, "a/" + path) }
        let a = try sandbox.connect("a")
        _ = try a.sync(as: mac, credentials: nil)
        let b = try sandbox.connect("b")
        _ = try b.sync(as: agent, credentials: nil)
        return (a, b)
    }
}

@Suite struct ConflictCopyTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func namesTheCopyNextToTheOriginal() {
        let stamp = Self.stamp(date)
        #expect(ConflictCopy.path(for: "a/b/Notes.md", date: date) { _ in false } == "a/b/Notes (conflict \(stamp)).md")
        #expect(ConflictCopy.path(for: "README", date: date) { _ in false } == "README (conflict \(stamp))")
        #expect(ConflictCopy.path(for: "x.md", date: date) { !$0.contains(" 3)") } == "x (conflict \(stamp) 3).md")
    }

    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: date)
    }
}

/// A temporary folder holding a bare remote and the Bases that sync with it.
final class Sandbox {
    let root: URL
    var remote: String { root.appending(path: "remote.git").path(percentEncoded: false) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "BaseKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try run("git", "init", "-q", "--bare", "-b", "main", remote)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func url(_ path: String) -> URL { root.appending(path: path) }
    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path(percentEncoded: false))
    }
    func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }
    func text(_ path: String) throws -> String { String(decoding: try data(path), as: UTF8.self) }

    func write(_ text: String, _ path: String) throws { try write(Data(text.utf8), path) }

    func write(_ data: Data, _ path: String) throws {
        let target = url(path)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
    }

    func connect(_ folder: String) throws -> BaseRepository {
        try FileManager.default.createDirectory(at: url(folder), withIntermediateDirectories: true)
        return try BaseRepository.connect(url(folder), to: remote)
    }

    /// Runs git against the remote and returns its trimmed output.
    func git(_ arguments: String...) throws -> String {
        try run(["git", "--git-dir", remote] + arguments)
    }

    @discardableResult
    func run(_ arguments: String...) throws -> String { try run(arguments) }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reaches GitHub over HTTPS. Run with `USUALBASE_NETWORK_TESTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["USUALBASE_NETWORK_TESTS"] == "1"))
struct GitNetworkTests {
    let sandbox = try! Sandbox()

    @Test func fetchesAPublicRepositoryOverHTTPS() throws {
        let base = try BaseRepository.connect(
            sandbox.url("public"), to: "https://github.com/libgit2/TestGitRepository.git")
        #expect(try base.fetchOrigin(nil) == "master")
    }

    @Test func reportsMissingCredentials() throws {
        let base = try BaseRepository.connect(
            sandbox.url("private"), to: "https://github.com/usual-labs-invalid/no-such-base.git")
        #expect(throws: SyncError.authenticationFailed) {
            try base.fetchOrigin(GitCredentials(username: "x-access-token", token: "not-a-token"))
        }
    }
}

@Suite struct RemoteAddressTests {
    @Test func takesHTTPSAndSplitsOffAToken() throws {
        let address = try RemoteAddress(parsing: " https://x:art_v1_abc?expires=1@example.com/base.git\n")
        #expect(address.url == "https://example.com/base.git")
        #expect(address.credentials == GitCredentials(username: "x", token: "art_v1_abc?expires=1"))
        #expect(try RemoteAddress(parsing: "https://github.com/me/notes.git").credentials == nil)
    }

    @Test func refusesSSHAndOtherSchemes() {
        #expect(throws: RemoteAddress.Problem.ssh) { try RemoteAddress(parsing: "git@github.com:me/notes.git") }
        #expect(throws: RemoteAddress.Problem.ssh) { try RemoteAddress(parsing: "ssh://git@github.com/me/notes") }
        #expect(throws: RemoteAddress.Problem.notHTTPS) { try RemoteAddress(parsing: "/Users/me/notes.git") }
        #expect(throws: RemoteAddress.Problem.empty) { try RemoteAddress(parsing: "  ") }
    }
}
