import Foundation
import Markdown

/// A piece of Markdown source and what it is. The editor turns spans into text attributes;
/// nothing here knows about fonts or colours.
public struct StyleSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Whole lines.
        case heading(level: Int)
        /// Punctuation that makes the Markdown: `#`, `**`, backticks, `>`, pipes, fences.
        case syntax
        case emphasis
        case strong
        case strikethrough
        case inlineCode
        /// Whole lines.
        case codeBlock
        /// Whole lines.
        case blockQuote
        /// The first line of a list item; the marker (and checkbox) are its first `prefixLength` UTF-16 units.
        case listLine(prefixLength: Int)
        case listMarker
        case taskBox(checked: Bool)
        /// The text of a checked task.
        case taskDone
        /// A link, a bare URL or an autolink, with where it points.
        case link(destination: String)
        case image
        /// Whole lines.
        case table
        /// The header row of a table.
        case tableHeader
        case html
    }

    public var kind: Kind
    public var range: NSRange

    public init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

public enum MarkdownHighlighter {
    /// Spans for a Markdown body (no front matter), outer blocks before the inline spans inside
    /// them, so applying them in order lets the inner ones win.
    public static func spans(for text: String) -> [StyleSpan] {
        var walker = Walker(map: SourceMap(text), source: text as NSString)
        walker.visit(Document(parsing: text))
        return walker.spans
    }
}

private struct Walker: MarkupWalker {
    let map: SourceMap
    let source: NSString
    var spans: [StyleSpan] = []

    mutating func add(_ kind: StyleSpan.Kind, _ range: NSRange?) {
        guard let range, range.length > 0 else { return }
        spans.append(StyleSpan(kind, range))
    }

    /// The parts of a node outside its children: `**` around bold, `[` and `](…)` around link text.
    mutating func markSyntax(around node: Markup) {
        guard let full = map.range(node.range) else { return }
        let ranges = node.children.compactMap { map.range($0.range) }
        guard let first = ranges.first, let last = ranges.last else { return }
        add(.syntax, NSRange(location: full.location, length: first.location - full.location))
        add(.syntax, NSRange(location: NSMaxRange(last), length: NSMaxRange(full) - NSMaxRange(last)))
    }

    mutating func visitHeading(_ heading: Heading) {
        add(.heading(level: heading.level), map.lines(heading.range))
        markSyntax(around: heading)
        descendInto(heading)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        add(.emphasis, map.range(emphasis.range))
        markSyntax(around: emphasis)
        descendInto(emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        add(.strong, map.range(strong.range))
        markSyntax(around: strong)
        descendInto(strong)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        add(.strikethrough, map.range(strikethrough.range))
        markSyntax(around: strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = map.range(inlineCode.range) else { return }
        add(.inlineCode, range)
        let ticks = backtickRun(at: range.location, limit: range.length / 2)
        add(.syntax, NSRange(location: range.location, length: ticks))
        add(.syntax, NSRange(location: NSMaxRange(range) - ticks, length: ticks))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard let lines = map.lines(codeBlock.range) else { return }
        add(.codeBlock, lines)
        // Fence lines (``` or ~~~) are syntax; an indented code block has none.
        let first = source.lineRange(for: NSRange(location: lines.location, length: 0))
        if isFence(first) { add(.syntax, contentRange(of: first)) }
        let last = source.lineRange(for: NSRange(location: max(NSMaxRange(lines) - 1, lines.location), length: 0))
        if last.location != first.location && isFence(last) { add(.syntax, contentRange(of: last)) }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        // The outermost quote marks every `>` on its lines, nested ones included.
        guard !isInsideQuote(blockQuote), let lines = map.lines(blockQuote.range) else {
            descendInto(blockQuote)
            return
        }
        add(.blockQuote, lines)
        var location = lines.location
        while location < NSMaxRange(lines) {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            add(.syntax, quoteMarkers(in: line))
            location = NSMaxRange(line)
        }
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        guard let itemRange = map.range(listItem.range) else { return }
        let line = source.lineRange(for: NSRange(location: itemRange.location, length: 0))
        let contentStart =
            listItem.child(at: 0).flatMap { map.range($0.range)?.location } ?? NSMaxRange(contentRange(of: line))
        add(.listLine(prefixLength: max(contentStart - line.location, 0)), line)

        // The marker runs from the first non-space character to the next space.
        var cursor = line.location
        while cursor < contentStart, isSpace(at: cursor) { cursor += 1 }
        let markerStart = cursor
        while cursor < contentStart, !isSpace(at: cursor) { cursor += 1 }
        add(.listMarker, NSRange(location: markerStart, length: cursor - markerStart))

        if let checkbox = listItem.checkbox {
            let prefix = source.substring(with: NSRange(location: cursor, length: contentStart - cursor)) as NSString
            let box = prefix.range(of: "[")
            if box.location != NSNotFound {
                add(.taskBox(checked: checkbox == .checked), NSRange(location: cursor + box.location, length: 3))
            }
            if checkbox == .checked {
                add(
                    .taskDone,
                    NSRange(location: contentStart, length: NSMaxRange(contentRange(of: line)) - contentStart))
            }
        }
        descendInto(listItem)
    }

    mutating func visitLink(_ link: Link) {
        add(.link(destination: link.destination ?? ""), map.range(link.range))
        markSyntax(around: link)
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        add(.image, map.range(image.range))
    }

    mutating func visitText(_ text: Text) {
        guard let range = map.range(text.range) else { return }
        for url in BareURLs.ranges(in: source, range: range) {
            add(.link(destination: source.substring(with: url)), url)
        }
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        add(.html, map.range(inlineHTML.range))
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        add(.html, map.lines(html.range))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        add(.syntax, map.range(thematicBreak.range))
    }

    mutating func visitTable(_ table: Table) {
        guard let lines = map.lines(table.range) else { return }
        add(.table, lines)
        var location = lines.location
        var index = 0
        while location < NSMaxRange(lines) {
            let line = source.lineRange(for: NSRange(location: location, length: 0))
            switch index {
            case 0: add(.tableHeader, line)
            case 1: add(.syntax, contentRange(of: line))  // the |---|---| row
            default: break
            }
            for pipe in pipes(in: line) { add(.syntax, NSRange(location: pipe, length: 1)) }
            location = NSMaxRange(line)
            index += 1
        }
        descendInto(table)
    }

    private func isInsideQuote(_ node: Markup) -> Bool {
        var parent = node.parent
        while let current = parent {
            if current is BlockQuote { return true }
            parent = current.parent
        }
        return false
    }

    // MARK: - Source scanning

    private func character(at offset: Int) -> unichar? {
        offset >= 0 && offset < source.length ? source.character(at: offset) : nil
    }

    private func isSpace(at offset: Int) -> Bool {
        let c = character(at: offset)
        return c == 0x20 || c == 0x09
    }

    private func backtickRun(at offset: Int, limit: Int) -> Int {
        var count = 0
        while count < limit, character(at: offset + count) == 0x60 { count += 1 }
        return count
    }

    /// A line without its line break.
    private func contentRange(of line: NSRange) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location, let c = character(at: end - 1), c == 0x0A || c == 0x0D { end -= 1 }
        return NSRange(location: line.location, length: end - line.location)
    }

    private func isFence(_ line: NSRange) -> Bool {
        let text = source.substring(with: contentRange(of: line)).trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("```") || text.hasPrefix("~~~")
    }

    /// The `>` markers at the start of a quote line, each with the space after it.
    private func quoteMarkers(in line: NSRange) -> NSRange? {
        var cursor = line.location
        var end = cursor
        while cursor < NSMaxRange(line) {
            while isSpace(at: cursor) { cursor += 1 }
            guard character(at: cursor) == 0x3E else { break }  // >
            cursor += 1
            if isSpace(at: cursor) { cursor += 1 }
            end = cursor
        }
        return end > line.location ? NSRange(location: line.location, length: end - line.location) : nil
    }

    /// Unescaped `|` characters in a table line.
    private func pipes(in line: NSRange) -> [Int] {
        var result: [Int] = []
        var escaped = false
        for offset in line.location..<NSMaxRange(line) {
            let c = source.character(at: offset)
            if c == 0x7C && !escaped { result.append(offset) }  // |
            escaped = c == 0x5C && !escaped  // \
        }
        return result
    }
}
