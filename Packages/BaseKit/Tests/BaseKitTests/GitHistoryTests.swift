import Foundation
import Testing

@testable import BaseKit

@Suite struct GitHistoryTests {
    let mac = GitIdentity(name: "Mac", email: "mac@example.com")
    let agent = GitIdentity(name: "Agent", email: "agent@example.com")
    let sandbox = try! Sandbox()

    @Test func listsTheCommitsThatChangedAFileNewestFirst() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try sandbox.write("one", "a/Notes/plan.md")
        try sandbox.write("x", "a/other.md")
        let base = try sandbox.connect("a")
        #expect(try base.history(of: "Notes/plan.md").isEmpty)
        #expect(try base.commitChanges(as: mac, now: start))
        try sandbox.write("y", "a/other.md")
        #expect(try base.commitChanges(as: agent, now: start + 60))
        try sandbox.write("two", "a/Notes/plan.md")
        #expect(try base.commitChanges(as: agent, now: start + 120))

        let history = try base.history(of: "Notes/plan.md")
        #expect(history.map(\.author) == ["Agent", "Mac"])
        #expect(history.map(\.summary) == ["Update Notes/plan.md", "Add 2 files"])
        #expect(history.first?.date == start + 120)
        #expect(history.first?.email == "agent@example.com")
        #expect(history.first?.id == (try sandbox.run("git", "-C", sandbox.url("a").path, "rev-parse", "HEAD")))
        #expect(try base.history(of: "other.md").count == 2)
        #expect(try base.history(of: "missing.md").isEmpty)
        #expect(try base.history(of: "Notes/plan.md", limit: 1).map(\.author) == ["Agent"])
    }

    @Test func includesTheCommitThatDeletedAFile() throws {
        try sandbox.write("one", "a/gone.md")
        let base = try sandbox.connect("a")
        #expect(try base.commitChanges(as: mac))
        try FileManager.default.removeItem(at: sandbox.url("a/gone.md"))
        try sandbox.write("keep", "a/keep.md")
        #expect(try base.commitChanges(as: agent))
        #expect(try base.history(of: "gone.md").map(\.author) == ["Agent", "Mac"])
    }
}
