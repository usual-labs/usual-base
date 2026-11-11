import AppKit
import BaseKit

extension NSAttributedString.Key {
    /// `"code"` or `"quote"` on whole lines; `BlockLayoutFragment` draws the background or bar.
    static let usualBlock = NSAttributedString.Key("labs.usual.base.block")
    /// A link's destination, for ⌘-click.
    static let usualLink = NSAttributedString.Key("labs.usual.base.link")
    /// Marks a task's `[ ]` box, which toggles on click.
    static let usualTaskBox = NSAttributedString.Key("labs.usual.base.task-box")
}

/// How each kind of span looks. Every style goes through here, so a new Markdown feature is a
/// new span kind and a new case below.
@MainActor
enum EditorTheme {
    static let bodyFont = NSFont.systemFont(ofSize: 15)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    static let syntaxColor = MarkdownColors.syntax

    static let baseParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.paragraphSpacing = 3
        return style
    }()

    static var base: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.textColor, .paragraphStyle: baseParagraph]
    }

    /// Restyles the whole text. Attribute changes don't count as edits, so this doesn't touch
    /// undo or the document's dirty state.
    static func apply(_ spans: [StyleSpan], to storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(base, range: full)
        for span in spans where NSMaxRange(span.range) <= storage.length {
            apply(span.kind, span.range, to: storage)
        }
        storage.endEditing()
    }

    /// Whether the character is ordinary text, not code, a link, or Markdown's own syntax (such as a link's
    /// destination). Reads the attributes `apply` set.
    static func isProse(at location: Int, in storage: NSTextStorage) -> Bool {
        let attributes = storage.attributes(at: location, effectiveRange: nil)
        if attributes[.usualLink] != nil || attributes[.usualBlock] as? String == "code" { return false }
        if attributes[.foregroundColor] as? NSColor == syntaxColor { return false }
        let font = attributes[.font] as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.monoSpace) != true
    }

    private static func apply(_ kind: StyleSpan.Kind, _ range: NSRange, to storage: NSTextStorage) {
        switch kind {
        case .heading(let level):
            let sizes: [CGFloat] = [26, 21, 18, 16, 15, 15]
            let size = sizes[min(max(level, 1), sizes.count) - 1]
            storage.addAttributes(
                [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .paragraphStyle: headingParagraph(level)],
                range: range
            )
        case .syntax:
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: range)
        case .emphasis:
            storage.applyFontTraits(.italicFontMask, range: range)
        case .strong:
            storage.applyFontTraits(.boldFontMask, range: range)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode:
            storage.addAttributes([.font: codeFont, .backgroundColor: EditorColors.codeBackground], range: range)
        case .codeBlock:
            storage.addAttributes([.font: codeFont, .paragraphStyle: codeParagraph, .usualBlock: "code"], range: range)
        case .blockQuote:
            storage.addAttributes(
                [.foregroundColor: MarkdownColors.secondary, .paragraphStyle: quoteParagraph, .usualBlock: "quote"],
                range: range
            )
        case .listLine(let prefixLength):
            // Hanging indent: wrapped lines line up with the text after the marker.
            let prefix = NSRange(location: range.location, length: min(prefixLength, range.length))
            let width = storage.attributedSubstring(from: prefix).size().width
            let current =
                storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let style = (current ?? baseParagraph).mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = style.firstLineHeadIndent + width
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: MarkdownColors.secondary, range: range)
        case .taskBox:
            storage.addAttributes([.foregroundColor: NSColor.controlAccentColor, .usualTaskBox: true], range: range)
        case .taskDone:
            storage.addAttributes(
                [
                    .foregroundColor: MarkdownColors.secondary,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ],
                range: range
            )
        case .link(let destination):
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .usualLink: destination], range: range)
        case .image, .html:
            storage.addAttribute(.foregroundColor, value: MarkdownColors.secondary, range: range)
        case .table:
            storage.addAttribute(.font, value: codeFont, range: range)
        case .tableHeader:
            storage.addAttribute(
                .font, value: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .semibold), range: range)
        }
    }

    private static func headingParagraph(_ level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.1
        style.paragraphSpacingBefore = level <= 2 ? 14 : 8
        style.paragraphSpacing = 4
        return style
    }

    private static let codeParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.15
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        style.tailIndent = -12
        return style
    }()

    private static let quoteParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.paragraphSpacing = 3
        style.firstLineHeadIndent = 14
        style.headIndent = 14
        return style
    }()
}
