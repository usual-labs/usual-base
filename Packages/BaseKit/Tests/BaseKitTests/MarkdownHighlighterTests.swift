import Foundation
import Testing

@testable import BaseKit

@Suite struct MarkdownHighlighterTests {
    /// The source text each span of `kind` covers.
    private func texts(_ kind: StyleSpan.Kind, in source: String) -> [String] {
        MarkdownHighlighter.spans(for: source)
            .filter { $0.kind == kind }
            .map { (source as NSString).substring(with: $0.range) }
    }

    @Test func headingsCoverTheLineAndDimTheirMarkers() {
        let source = "## Hé **bold**\nnext"
        #expect(texts(.heading(level: 2), in: source) == ["## Hé **bold**\n"])
        #expect(texts(.syntax, in: source) == ["## ", "**", "**"])
        #expect(texts(.strong, in: source) == ["**bold**"])
    }

    @Test func offsetsAreUTF16AfterMultibyteText() {
        let source = "😀 é `code` and *it*"
        #expect(texts(.inlineCode, in: source) == ["`code`"])
        #expect(texts(.emphasis, in: source) == ["*it*"])
    }

    @Test func crlfLinesStayAligned() {
        let source = "first\r\n\r\n**second**\r\n"
        #expect(texts(.strong, in: source) == ["**second**"])
    }

    @Test func tasksMarkTheirBoxAndDoneText() {
        let source = "- [ ] open\n- [x] done\n  1. nested"
        #expect(texts(.taskBox(checked: false), in: source) == ["[ ]"])
        #expect(texts(.taskBox(checked: true), in: source) == ["[x]"])
        #expect(texts(.taskDone, in: source) == ["done"])
        #expect(texts(.listMarker, in: source) == ["-", "-", "1."])
        let prefixes = MarkdownHighlighter.spans(for: source).compactMap { span -> Int? in
            if case .listLine(let length) = span.kind { return length }
            return nil
        }
        #expect(prefixes == [6, 6, 5])
    }

    @Test func linksKeepTheirDestinationAndBareURLsAreFound() {
        let source = "See [notes](docs/notes.md) and https://usual.dev/base, then (https://example.com)."
        let links = MarkdownHighlighter.spans(for: source).compactMap { span -> String? in
            if case .link(let destination) = span.kind { return destination }
            return nil
        }
        #expect(links == ["docs/notes.md", "https://usual.dev/base", "https://example.com"])
        #expect(texts(.syntax, in: source) == ["[", "](docs/notes.md)"])
    }

    @Test func codeBlocksDimOnlyTheirFences() {
        let source = "```swift\nlet a = \"**no**\"\n```\n"
        #expect(texts(.codeBlock, in: source) == [source])
        #expect(texts(.syntax, in: source) == ["```swift", "```"])
        #expect(texts(.strong, in: source).isEmpty)
    }

    @Test func quotesAndTables() {
        let quote = "> > nested\n> more"
        #expect(texts(.syntax, in: quote) == ["> > ", "> "])
        let table = "| a | b |\n|---|---|\n| 1 | 2 |"
        #expect(texts(.tableHeader, in: table) == ["| a | b |\n"])
        #expect(texts(.syntax, in: table).filter { $0 != "|" } == ["|---|---|"])
    }
}
