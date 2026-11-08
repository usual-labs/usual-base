import AppKit
import Markdown

/// Turns a Markdown body into text for reading: the syntax is gone, list items get markers,
/// and quotes, code, tables and rules become text blocks.
///
/// The result needs TextKit 1. TextKit 2 can't lay out `NSTextTable`, so a TextKit 2 view would
/// switch itself to TextKit 1 the first time it showed a table.
public enum MarkdownRenderer {
    public struct Style {
        public var bodyFont: NSFont
        public var codeFont: NSFont
        /// The widest the text gets. Wider pictures are scaled down to it, and table columns
        /// share it out.
        public var textWidth: CGFloat

        public init(bodyFont: NSFont, codeFont: NSFont, textWidth: CGFloat) {
            self.bodyFont = bodyFont
            self.codeFont = codeFont
            self.textWidth = textWidth
        }
    }

    /// `image` returns the picture an image's source names, or nil to show the image's
    /// description as a link instead.
    public static func render(
        _ body: String, style: Style, image: @escaping (String) -> NSImage? = { _ in nil }
    ) -> NSAttributedString {
        var renderer = Renderer(style: style, image: image)
        renderer.render(Document(parsing: body).children, in: Renderer.Context())
        return renderer.output
    }
}

/// Walks the document's blocks and writes them out one paragraph at a time.
struct Renderer {
    /// What surrounds the paragraphs being written.
    struct Context {
        /// Quotes, code, tables and rules around the text, outermost first.
        var blocks: [NSTextBlock] = []
        /// How far lists push the text in, inside the innermost block.
        var indent: CGFloat = 0
        var listDepth = 0
        var color: NSColor = .labelColor
    }

    /// A list item's marker, waiting for the item's first line.
    struct Marker {
        var text: NSAttributedString
        var indent: CGFloat
        var contentIndent: CGFloat
        var spacing: CGFloat
        var isDone: Bool
    }

    static let headingSizes: [CGFloat] = [26, 21, 18, 16, 15, 15]
    static let bullets = ["•", "◦", "▪"]

    let style: MarkdownRenderer.Style
    let image: (String) -> NSImage?
    let output = NSMutableAttributedString()
    private var marker: Marker?
    /// Nothing is written yet in the current block, so the next paragraph needs no space above it.
    private var atBlockStart = true
    private var afterHeading = false

    /// Made once per render: building a symbol image is slow enough to show in long task lists.
    let uncheckedBox: NSImage?
    let checkedBox: NSImage?

    init(style: MarkdownRenderer.Style, image: @escaping (String) -> NSImage?) {
        self.style = style
        self.image = image
        uncheckedBox = Self.symbolImage(
            "square", description: "To do", font: style.bodyFont, color: .secondaryLabelColor)
        checkedBox = Self.symbolImage(
            "checkmark.square.fill", description: "Done", font: style.bodyFont, color: .controlAccentColor)
    }

    mutating func render(_ nodes: some Sequence<Markup>, in context: Context) {
        for node in nodes { render(node, in: context) }
    }

    mutating func render(_ node: Markup, in context: Context) {
        switch node {
        case let heading as Heading:
            let level = min(max(heading.level, 1), Self.headingSizes.count)
            let font = NSFont.systemFont(ofSize: Self.headingSizes[level - 1], weight: .semibold)
            write(
                inlines(heading, font: font, color: context.color), in: context, spacing: level <= 2 ? 24 : 18,
                lineHeight: 1.1, font: font)
            afterHeading = true
        case let paragraph as Paragraph:
            write(inlines(paragraph, font: style.bodyFont, color: context.color), in: context, spacing: 10)
        case let list as UnorderedList:
            self.list(Array(list.listItems), start: nil, in: context)
        case let list as OrderedList:
            self.list(Array(list.listItems), start: Int(list.startIndex), in: context)
        case let quote as BlockQuote:
            self.quote(quote, in: context)
        case let code as CodeBlock:
            self.code(code.code, in: context)
        case let table as Table:
            self.table(table, in: context)
        case is ThematicBreak:
            rule(in: context)
        case let html as HTMLBlock:
            self.html(html.rawHTML, in: context)
        default:
            render(node.children, in: context)
        }
    }

    // MARK: - Paragraphs

    /// Writes one paragraph, with the waiting list marker in front of it if there is one.
    mutating func write(
        _ content: NSAttributedString, in context: Context, spacing: CGFloat, lineHeight: CGFloat = 1.2,
        alignment: NSTextAlignment = .natural, font: NSFont? = nil
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeight
        paragraph.alignment = alignment
        paragraph.textBlocks = context.blocks
        paragraph.firstLineHeadIndent = context.indent
        paragraph.headIndent = context.indent
        let line = NSMutableAttributedString()
        let body = NSMutableAttributedString(attributedString: content)
        if let marker {
            self.marker = nil
            paragraph.paragraphSpacingBefore = space(marker.spacing)
            paragraph.firstLineHeadIndent = marker.indent
            paragraph.headIndent = marker.contentIndent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: marker.contentIndent)]
            line.append(marker.text)
            line.append(NSAttributedString(string: "\t", attributes: [.font: style.bodyFont]))
            if marker.isDone {
                body.addAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ],
                    range: NSRange(location: 0, length: body.length))
            }
        } else {
            paragraph.paragraphSpacingBefore = space(spacing)
        }
        line.append(body)
        line.append(NSAttributedString(string: "\n", attributes: [.font: font ?? style.bodyFont]))
        line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
        output.append(line)
    }

    /// The space above the next paragraph: none at the top of a block, and less under a heading.
    mutating func space(_ requested: CGFloat) -> CGFloat {
        defer {
            atBlockStart = false
            afterHeading = false
        }
        if atBlockStart { return 0 }
        return afterHeading ? min(requested, 8) : requested
    }

    /// A list item that starts with a block, not text, gets its marker on a line of its own.
    mutating func flushMarker(in context: Context) {
        if marker != nil { write(NSAttributedString(), in: context, spacing: 0) }
    }

    // MARK: - Blocks

    private mutating func list(_ items: [ListItem], start: Int?, in context: Context) {
        flushMarker(in: context)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: style.bodyFont.pointSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let markers = items.enumerated().map { index, item -> NSAttributedString in
            if let checkbox = item.checkbox { return self.checkbox(checked: checkbox == .checked) }
            if let start { return NSAttributedString(string: "\(start + index).", attributes: attributes) }
            return NSAttributedString(
                string: Self.bullets[context.listDepth % Self.bullets.count], attributes: attributes)
        }
        // The marker with the most characters is the widest; measuring each one is slow.
        let widest = markers.max { $0.length < $1.length }?.size().width ?? 0
        let contentIndent = context.indent + max(ceil(widest) + 8, 20)
        for (index, item) in items.enumerated() {
            var inner = context
            inner.indent = contentIndent
            inner.listDepth += 1
            let firstSpacing: CGFloat = context.listDepth == 0 ? 10 : 4
            marker = Marker(
                text: markers[index], indent: context.indent, contentIndent: contentIndent,
                spacing: index == 0 ? firstSpacing : 4, isDone: item.checkbox == .checked)
            render(item.children, in: inner)
            flushMarker(in: inner)
        }
    }

    /// Writes paragraphs inside `block`. A plain outer block holds the space above it and the
    /// list indent, because AppKit paints a block's background over its own margins.
    private mutating func nest(
        _ block: NSTextBlock, in context: Context, spacing: CGFloat, body: (inout Renderer, Context) -> Void
    ) {
        flushMarker(in: context)
        let frame = FullWidthTextBlock()
        frame.setWidth(space(spacing), type: .absoluteValueType, for: .margin, edge: .minY)
        frame.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        var inner = context
        inner.blocks += [frame, block]
        inner.indent = 0
        atBlockStart = true
        body(&self, inner)
        atBlockStart = false
    }

    private mutating func quote(_ quote: BlockQuote, in context: Context) {
        let block = FullWidthTextBlock()
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(.tertiaryLabelColor, for: .minX)
        block.setWidth(14, type: .absoluteValueType, for: .padding, edge: .minX)
        nest(block, in: context, spacing: 10) { renderer, inner in
            var inner = inner
            inner.color = .secondaryLabelColor
            renderer.render(quote.children, in: inner)
        }
    }

    private mutating func code(_ code: String, in context: Context) {
        let block = FullWidthTextBlock()
        block.backgroundColor = .quaternarySystemFill
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        block.setWidth(14, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(14, type: .absoluteValueType, for: .padding, edge: .maxX)
        var lines = code.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        let attributes: [NSAttributedString.Key: Any] = [.font: style.codeFont, .foregroundColor: NSColor.labelColor]
        nest(block, in: context, spacing: 10) { renderer, inner in
            for line in lines {
                renderer.write(
                    NSAttributedString(string: line, attributes: attributes), in: inner, spacing: 0, lineHeight: 1.15,
                    font: renderer.style.codeFont)
            }
        }
    }

    private mutating func rule(in context: Context) {
        let block = FullWidthTextBlock()
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setBorderColor(.separatorColor, for: .maxY)
        block.setWidth(6, type: .absoluteValueType, for: .margin, edge: .maxY)
        nest(block, in: context, spacing: 14) { renderer, inner in
            let font = NSFont.systemFont(ofSize: 2)
            renderer.write(NSAttributedString(), in: inner, spacing: 0, lineHeight: 1, font: font)
        }
    }

    /// Raw HTML shows as dimmed source, since there's no web view to draw it. Comments stay
    /// hidden, as they do on GitHub.
    private mutating func html(_ raw: String, in context: Context) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !(trimmed.hasPrefix("<!--") && trimmed.hasSuffix("-->")) else { return }
        let text = trimmed.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\u{2028}")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.codeFont, .foregroundColor: NSColor.secondaryLabelColor,
        ]
        write(NSAttributedString(string: text, attributes: attributes), in: context, spacing: 10)
    }
}

/// A text block as wide as the space it's in. A plain `NSTextBlock` is only as wide as its width
/// value, which defaults to almost nothing, and a 100% width would leave out its padding.
final class FullWidthTextBlock: NSTextBlock {
    override func rectForLayout(
        at startingPoint: NSPoint, in rect: NSRect, textContainer: NSTextContainer, characterRange: NSRange
    ) -> NSRect {
        var layout = super.rectForLayout(
            at: startingPoint, in: rect, textContainer: textContainer, characterRange: characterRange)
        let trailing =
            width(for: .margin, edge: .maxX) + width(for: .border, edge: .maxX) + width(for: .padding, edge: .maxX)
        layout.size.width = max(rect.maxX - layout.minX - trailing, 1)
        return layout
    }
}
