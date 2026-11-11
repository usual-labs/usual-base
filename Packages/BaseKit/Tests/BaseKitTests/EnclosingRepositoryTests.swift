import Foundation
import Testing

@testable import BaseKit

@Suite struct EnclosingRepositoryTests {
    let sandbox: Sandbox

    init() throws {
        sandbox = try Sandbox()
        try sandbox.write("code\n", "project/src/app.js")
        try sandbox.run("git", "-C", sandbox.url("project").path(percentEncoded: false), "init", "-q")
    }

    private var project: String { sandbox.url("project").path(percentEncoded: false) }
    private func status() throws -> String { try sandbox.run("git", "-C", project, "status", "--porcelain") }

    @Test func makesTheProjectIgnoreABaseInsideIt() throws {
        let base = sandbox.url("project/docs/notes")
        try sandbox.write("# Plan\n", "project/docs/notes/Plan.md")
        _ = try sandbox.connect("project/docs/notes")
        let root = try #require(EnclosingRepository.ignore(base))
        #expect(root.resolvingSymlinksInPath() == sandbox.url("project").resolvingSymlinksInPath())
        #expect(try sandbox.text("project/.git/info/exclude").hasSuffix("\n/docs/notes/\n"))
        #expect(try status() == "?? src/")
    }

    @Test func leavesAFolderAloneThatIsIgnoredAlready() throws {
        try sandbox.write("/base/\n", "project/.gitignore")
        let before = try sandbox.text("project/.git/info/exclude")
        #expect(EnclosingRepository.ignore(sandbox.url("project/base")) != nil)
        #expect(try sandbox.text("project/.git/info/exclude") == before)
    }

    @Test func escapesCharactersThatPatternsGiveMeaningTo() throws {
        try sandbox.write("# Plan\n", "project/[draft] #1/Plan.md")
        #expect(EnclosingRepository.ignore(sandbox.url("project/[draft] #1")) != nil)
        #expect(try sandbox.text("project/.git/info/exclude").hasSuffix("\n/\\[draft\\] \\#1/\n"))
        #expect(try status() == "?? src/")
    }

    @Test func doesNothingOutsideARepository() throws {
        #expect(EnclosingRepository.ignore(sandbox.url("elsewhere/base")) == nil)
    }
}
