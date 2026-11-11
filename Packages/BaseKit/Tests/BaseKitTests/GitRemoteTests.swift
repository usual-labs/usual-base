import Foundation
import Testing

@testable import BaseKit

private let testRemote = ProcessInfo.processInfo.environment["USUALBASE_TEST_REMOTE"]
private let testToken = ProcessInfo.processInfo.environment["USUALBASE_TEST_TOKEN"]
private let testReadToken = ProcessInfo.processInfo.environment["USUALBASE_TEST_READ_TOKEN"]

/// Syncs through a real HTTPS remote that needs a token, such as a private GitHub repository or a
/// Cloudflare Artifacts repository. Every test adds files with unique names, so the remote may hold
/// anything, but use a scratch repository: the tests push to its default branch.
///
///     USUALBASE_TEST_REMOTE=https://… USUALBASE_TEST_TOKEN=… swift test --filter GitRemoteTests
///
/// `USUALBASE_TEST_READ_TOKEN`, if set, is a read-only token for the same remote.
@Suite(.serialized, .enabled(if: testRemote != nil && testToken != nil))
struct GitRemoteTests {
    static let remote = testRemote
    static let token = testToken

    let mac = GitIdentity(name: "Mac", email: "mac@example.com")
    let agent = GitIdentity(name: "Agent", email: "agent@example.com")
    let sandbox = try! Sandbox()
    let name = "test-\(UUID().uuidString.prefix(8)).md"
    var credentials: GitCredentials { GitCredentials(username: "x", token: Self.token!) }

    func connect(_ folder: String) throws -> BaseRepository {
        try FileManager.default.createDirectory(at: sandbox.url(folder), withIntermediateDirectories: true)
        return try BaseRepository.connect(sandbox.url(folder), to: Self.remote!)
    }

    /// Two Bases on the remote's current state.
    func twoBases() throws -> (BaseRepository, BaseRepository) {
        let a = try connect("a")
        _ = try a.sync(as: mac, credentials: credentials)
        let b = try connect("b")
        _ = try b.sync(as: agent, credentials: credentials)
        return (a, b)
    }

    @Test func carriesEditsBothWays() throws {
        let (a, b) = try twoBases()
        try sandbox.write("from mac\n", "a/\(name)")
        #expect(try a.sync(as: mac, credentials: credentials).pushed)
        #expect(try b.sync(as: agent, credentials: credentials).updatedFromRemote)
        #expect(try sandbox.text("b/\(name)") == "from mac\n")

        try sandbox.write("from mac\nfrom agent\n", "b/\(name)")
        #expect(try b.sync(as: agent, credentials: credentials).pushed)
        _ = try a.sync(as: mac, credentials: credentials)
        #expect(try sandbox.text("a/\(name)") == "from mac\nfrom agent\n")
    }

    @Test func keepsACopyWhenEditsClash() throws {
        try sandbox.write("draft\n", "a/\(name)")
        let a = try connect("a")
        _ = try a.sync(as: mac, credentials: credentials)
        let b = try connect("b")
        _ = try b.sync(as: agent, credentials: credentials)
        try sandbox.write("mac's version\n", "a/\(name)")
        try sandbox.write("agent's version\n", "b/\(name)")
        _ = try a.sync(as: mac, credentials: credentials)
        let report = try b.sync(as: agent, credentials: credentials)
        let copy = try #require(report.conflicts.first).copy
        #expect(try sandbox.text("b/\(name)") == "mac's version\n")
        #expect(try sandbox.text("b/" + copy) == "agent's version\n")
        // Clean up the remote.
        try FileManager.default.removeItem(at: sandbox.url("b/" + copy))
        try FileManager.default.removeItem(at: sandbox.url("b/\(name)"))
        _ = try b.sync(as: agent, credentials: credentials)
    }

    @Test func fetchesAndRetriesWhenAPushIsRefused() throws {
        let (a, b) = try twoBases()
        try sandbox.write("from mac\n", "a/\(name)")
        try sandbox.write("from agent\n", "b/agent-\(name)")
        _ = try a.sync(as: mac, credentials: credentials)
        let report = try b.sync(as: agent, credentials: credentials, fetch: false)
        #expect(report.pushed && report.updatedFromRemote)
        #expect(try sandbox.text("b/\(name)") == "from mac\n")
    }

    @Test func reportsAWrongToken() throws {
        let a = try connect("a")
        #expect(throws: SyncError.authenticationFailed) {
            _ = try a.sync(as: mac, credentials: GitCredentials(username: "x", token: "not-a-token"))
        }
    }

    @Test(.enabled(if: testReadToken != nil))
    func reportsAReadOnlyTokenOnPush() throws {
        let readOnly = GitCredentials(username: "x", token: testReadToken!)
        let a = try connect("a")
        _ = try a.sync(as: mac, credentials: readOnly)
        try sandbox.write("not allowed\n", "a/\(name)")
        do {
            _ = try a.sync(as: mac, credentials: readOnly)
            Issue.record("the push went through with a read-only token")
        } catch {
            // Records what the app shows today; a 403 isn't mapped to a credentials problem yet.
            print("read-only push error: \(error)")
        }
    }
}
