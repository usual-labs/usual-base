import Foundation
import Testing

@testable import BaseKit

@Suite struct MarkdownFileTests {
    @Test func splitsFrontMatterAndKeepsExactBytes() throws {
        let text = "---\r\nname: Usual\r\ntags: [a, b]\r\n---\r\n# Title\r\nBody\r\n"
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        let file = try #require(MarkdownFile(data: data))
        #expect(file.byteOrderMark)
        #expect(file.frontMatter == "---\r\nname: Usual\r\ntags: [a, b]\r\n---\r\n")
        #expect(file.body == "# Title\r\nBody\r\n")
        #expect(file.frontMatterYAML == "name: Usual\r\ntags: [a, b]\r\n")
        #expect(file.data == data)
    }

    @Test func withoutClosingFenceEverythingIsBody() {
        let file = MarkdownFile(text: "---\nnot: closed\n# Heading\n")
        #expect(file.frontMatter.isEmpty)
        #expect(file.body == "---\nnot: closed\n# Heading\n")
        #expect(file.frontMatterYAML == nil)
    }

    @Test func acceptsDotsAsClosingFenceAndEndOfFile() {
        let dots = MarkdownFile(text: "---\na: 1\n...\nbody")
        #expect(dots.frontMatter == "---\na: 1\n...\n")
        let endOfFile = MarkdownFile(text: "---\na: 1\n---")
        #expect(endOfFile.frontMatter == "---\na: 1\n---")
        #expect(endOfFile.body.isEmpty)
        #expect(endOfFile.frontMatterYAML == "a: 1\n")
    }

    @Test func aThematicBreakAloneIsNotFrontMatter() {
        #expect(MarkdownFile(text: "---").frontMatter.isEmpty)
        #expect(MarkdownFile(text: "----\na\n----\n").frontMatter.isEmpty)
    }

    @Test func replacingYAMLKeepsTheFences() {
        let file = MarkdownFile(text: "--- \r\na: 1\r\n...\r\nbody")
        let edited = file.replacingFrontMatterYAML("a: 2")
        #expect(edited.frontMatter == "--- \r\na: 2\r\n...\r\n")
        #expect(edited.body == "body")
    }

    @Test func rejectsNonUTF8() {
        #expect(MarkdownFile(data: Data([0xFF, 0xFE, 0x00])) == nil)
    }
}

@Suite struct FrontMatterTests {
    @Test func readsPropertiesInOrderAndFlattensNestedKeys() {
        let matter = FrontMatter(
            yaml: """
                name: usual-base
                description: Shared agent memory
                metadata:
                  type: project
                tags: [notes, agents]
                updated: 2026-11-06
                draft: true
                source: https://usual.dev
                """
        )
        #expect(matter.problem == nil)
        #expect(
            matter.properties.map(\.key) == [
                "name", "description", "metadata.type", "tags", "updated", "draft", "source",
            ])
        #expect(matter.title == "usual-base")
        #expect(matter.summary == "Shared agent memory")
        #expect(matter.properties[3].value == .list(["notes", "agents"]))
        #expect(matter.properties[5].value == .flag(true))
        #expect(matter.properties[6].value == .link(URL(string: "https://usual.dev")!))
        guard case .date = matter.properties[4].value else {
            Issue.record("updated should be a date")
            return
        }
    }

    @Test func quotedValuesStayText() {
        let matter = FrontMatter(yaml: "updated: \"2026-11-06\"\nflag: 'yes'")
        #expect(matter.properties[0].value == .text("2026-11-06"))
        #expect(matter.properties[1].value == .text("yes"))
    }

    @Test func reportsInvalidYAML() {
        #expect(FrontMatter(yaml: "a: [unclosed").problem != nil)
        #expect(FrontMatter(yaml: "- just\n- a list").problem != nil)
        #expect(FrontMatter(yaml: "").properties.isEmpty)
    }
}
