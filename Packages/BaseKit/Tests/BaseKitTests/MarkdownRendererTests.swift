import AppKit
import Testing

@testable import BaseKit

@Suite struct MarkdownRendererTests {
    private let style = MarkdownRenderer.Style(
        bodyFont: .systemFont(ofSize: 15), codeFont: .monospacedSystemFont(ofSize: 13.5, weight: .regular),
        textWidth: 600)

    private func render(_ source: String, image: @escaping (String) -> NSImage? = { _ in nil }) -> NSAttributedString {
        MarkdownRenderer.render(source, style: style, image: image)
    }

    /// The attributes on the first occurrence of `text`.
    private func attributes(of text: String, in rendered: NSAttributedString) -> [NSAttributedString.Key: Any] {
        let range = (rendered.string as NSString).range(of: text)
        #expect(range.location != NSNotFound, "“\(text)” isn't in “\(rendered.string)”")
        guard range.location != NSNotFound else { return [:] }
        return rendered.attributes(at: range.location, effectiveRange: nil)
    }

    private func paragraphStyle(of text: String, in rendered: NSAttributedString) -> NSParagraphStyle? {
        attributes(of: text, in: rendered)[.paragraphStyle] as? NSParagraphStyle
    }

    private func traits(of text: String, in rendered: NSAttributedString) -> NSFontDescriptor.SymbolicTraits {
        (attributes(of: text, in: rendered)[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
    }

    @Test func dropsTheSyntaxAndKeepsTheStyles() {
        let rendered = render("# Title\n\nSome **bold**, *slanted*, ~~gone~~ and `code`.\nSame paragraph.")
        #expect(rendered.string == "Title\nSome bold, slanted, gone and code. Same paragraph.\n")
        #expect(traits(of: "bold", in: rendered).contains(.bold))
        #expect(traits(of: "slanted", in: rendered).contains(.italic))
        #expect(traits(of: "code", in: rendered).contains(.monoSpace))
        #expect(attributes(of: "gone", in: rendered)[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect((attributes(of: "Title", in: rendered)[.font] as? NSFont)?.pointSize == 26)
    }

    @Test func linksKeepTheirDestinationAndBareURLsBecomeLinks() {
        let rendered = render("See [notes](Notes/Ideas.md#top) and https://example.com/a_(b).")
        #expect(rendered.string == "See notes and https://example.com/a_(b).\n")
        #expect(attributes(of: "notes", in: rendered)[.link] as? String == "Notes/Ideas.md#top")
        #expect(attributes(of: "https", in: rendered)[.link] as? String == "https://example.com/a_(b)")
        #expect(attributes(of: ".\n", in: rendered)[.link] == nil)
    }

    @Test func listsGetMarkersAndNestDeeper() {
        let rendered = render("- one\n  - inner\n- two\n\n3. third\n4. fourth")
        #expect(rendered.string == "•\tone\n◦\tinner\n•\ttwo\n3.\tthird\n4.\tfourth\n")
        let outer = paragraphStyle(of: "one", in: rendered)
        let inner = paragraphStyle(of: "inner", in: rendered)
        #expect(outer?.firstLineHeadIndent == 0)
        #expect((outer?.headIndent ?? 0) > 0)
        #expect(inner?.firstLineHeadIndent == outer?.headIndent)
        #expect(inner?.tabStops.first?.location == inner?.headIndent)
    }

    @Test func tasksShowABoxAndDoneTasksAreStruckThrough() {
        let rendered = render("- [ ] todo\n- [x] done")
        #expect(rendered.string == "\u{FFFC}\ttodo\n\u{FFFC}\tdone\n")
        #expect(rendered.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)
        #expect(attributes(of: "todo", in: rendered)[.strikethroughStyle] == nil)
        #expect(attributes(of: "done", in: rendered)[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test func tablesBecomeTextTablesWithOneCellPerParagraph() throws {
        let rendered = render("| Name | **Count** |\n|:-----|------:|\n| apples | 3 |\n| pears |")
        #expect(rendered.string == "Name\nCount\napples\n3\npears\n\n")
        var cells: [(row: Int, column: Int, alignment: NSTextAlignment)] = []
        var tables = Set<ObjectIdentifier>()
        (rendered.string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: rendered.length), options: .byParagraphs
        ) { _, range, _, _ in
            let style =
                rendered.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            guard let block = style?.textBlocks.last as? NSTextTableBlock else { return }
            cells.append((block.startingRow, block.startingColumn, style?.alignment ?? .natural))
            tables.insert(ObjectIdentifier(block.table))
        }
        #expect(cells.map(\.row) == [0, 0, 1, 1, 2, 2])
        #expect(cells.map(\.column) == [0, 1, 0, 1, 0, 1])
        #expect(cells.map(\.alignment) == [.left, .right, .left, .right, .left, .right])
        #expect(tables.count == 1)
        #expect(traits(of: "Name", in: rendered).contains(.bold))
        #expect(!traits(of: "apples", in: rendered).contains(.bold))
    }

    @Test func tableColumnsShareTheWidthByTheirText() {
        func cells(_ source: String) -> [NSTextTableBlock] {
            let rendered = render(source)
            var result: [NSTextTableBlock] = []
            rendered.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: rendered.length)) {
                value, _, _ in
                if let cell = (value as? NSParagraphStyle)?.textBlocks.last as? NSTextTableBlock,
                    result.last !== cell
                {
                    result.append(cell)
                }
            }
            return result
        }
        let long = String(repeating: "words that need room ", count: 8)
        let wide = cells("| A | B |\n|---|---|\n| short | \(long) |")
        #expect(wide[3].contentWidth > 3 * wide[2].contentWidth)
        #expect(wide[0].table.contentWidth == 100)
        let narrow = cells("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(narrow[0].table.contentWidth < 30)
        #expect(abs(narrow[0].contentWidth - narrow[1].contentWidth) < 5)
    }

    @Test func codeBlocksKeepTheirLinesInOneBlock() {
        let rendered = render("```swift\nlet x = 1\r\n\r\nlet y = **2**\n```\n\nAfter")
        #expect(rendered.string == "let x = 1\n\nlet y = **2**\nAfter\n")
        let first = paragraphStyle(of: "let x", in: rendered)?.textBlocks.last
        let last = paragraphStyle(of: "let y", in: rendered)?.textBlocks.last
        #expect(first != nil && first === last)
        #expect(first?.backgroundColor != nil)
        #expect(paragraphStyle(of: "After", in: rendered)?.textBlocks.isEmpty == true)
    }

    @Test func quotesDimTheirTextInsideABlock() {
        let rendered = render("> quoted *text*\n\nplain")
        #expect(rendered.string == "quoted text\nplain\n")
        #expect(paragraphStyle(of: "quoted", in: rendered)?.textBlocks.count == 2)
        #expect(attributes(of: "quoted", in: rendered)[.foregroundColor] as? NSColor == MarkdownColors.secondary)
        #expect(attributes(of: "plain", in: rendered)[.foregroundColor] as? NSColor == .labelColor)
    }

    @Test func htmlCommentsAreHiddenAndOtherHTMLShowsAsSource() {
        let rendered = render("<!-- generated -->\n\nText<br>more <span>x</span>\n\n<div>\nblock\n</div>")
        #expect(rendered.string == "Text\u{2028}more <span>x</span>\n<div>\u{2028}block\u{2028}</div>\n")
    }

    @Test func imagesLoadOrFallBackToALinkedDescription() {
        let picture = NSImage(size: NSSize(width: 1200, height: 300))
        let rendered = render("![Chart](chart.png) and ![Map](https://example.com/map.png)") { source in
            source == "chart.png" ? picture : nil
        }
        let attachment = rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        #expect(attachment?.image === picture)
        #expect(attachment?.bounds.size == CGSize(width: 600, height: 150))
        #expect(rendered.string.hasSuffix(" Map\n"))
        #expect(attributes(of: "Map", in: rendered)[.link] as? String == "https://example.com/map.png")
    }

    @Test func spacingSeparatesBlocksButNotTheFirstOne() {
        let rendered = render("First\n\nSecond")
        #expect(paragraphStyle(of: "First", in: rendered)?.paragraphSpacingBefore == 0)
        #expect((paragraphStyle(of: "Second", in: rendered)?.paragraphSpacingBefore ?? 0) > 0)
    }
}
