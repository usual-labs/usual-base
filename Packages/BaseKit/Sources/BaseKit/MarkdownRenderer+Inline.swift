import AppKit
import Markdown

extension Renderer {
    /// The text inside a paragraph, heading or table cell, without its Markdown syntax.
    func inlines(_ container: Markup, font: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        append(container.children, to: result, attributes: [.font: font, .foregroundColor: color])
        return result
    }

    private func append(
        _ nodes: some Sequence<Markup>, to result: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) {
        for node in nodes { append(node, to: result, attributes: attributes) }
    }

    private func append(
        _ node: Markup, to result: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]
    ) {
        var attributes = attributes
        let font = attributes[.font] as? NSFont ?? style.bodyFont
        switch node {
        case let text as Text:
            appendText(text.string, to: result, attributes: attributes)
        case is SoftBreak:
            result.append(NSAttributedString(string: " ", attributes: attributes))
        case is LineBreak:
            result.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
        case is Emphasis:
            attributes[.font] = font.adding(.italic)
            append(node.children, to: result, attributes: attributes)
        case is Strong:
            attributes[.font] = font.adding(.bold)
            append(node.children, to: result, attributes: attributes)
        case is Strikethrough:
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            append(node.children, to: result, attributes: attributes)
        case let code as InlineCode:
            appendCode(code.code, to: result, attributes: attributes)
        case let symbol as SymbolLink:
            appendCode(symbol.destination ?? "", to: result, attributes: attributes)
        case let link as Link:
            if let destination = link.destination, !destination.isEmpty { attributes[.link] = destination }
            append(node.children, to: result, attributes: attributes)
        case let image as Image:
            appendImage(image, to: result, attributes: attributes)
        case let html as InlineHTML:
            appendHTML(html.rawHTML, to: result, attributes: attributes)
        default:
            append(node.children, to: result, attributes: attributes)
        }
    }

    /// Plain text, with any bare `https://…` addresses in it made into links.
    private func appendText(
        _ text: String, to result: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]
    ) {
        let start = result.length
        result.append(NSAttributedString(string: text, attributes: attributes))
        guard attributes[.link] == nil else { return }
        let added = NSRange(location: start, length: result.length - start)
        for url in BareURLs.ranges(in: result.string as NSString, range: added) {
            result.addAttribute(.link, value: (result.string as NSString).substring(with: url), range: url)
        }
    }

    private func appendCode(
        _ code: String, to result: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]
    ) {
        var attributes = attributes
        let font = attributes[.font] as? NSFont ?? style.bodyFont
        attributes[.font] = NSFont(descriptor: style.codeFont.fontDescriptor, size: font.pointSize * 0.9) ?? font
        attributes[.backgroundColor] = MarkdownColors.codeBackground
        result.append(NSAttributedString(string: code, attributes: attributes))
    }

    /// A picture `image` can load, scaled to fit; otherwise its description, linked to its source.
    private func appendImage(
        _ node: Image, to result: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]
    ) {
        let source = node.source ?? ""
        if !source.isEmpty, let picture = image(source), picture.size.width > 0 {
            let attachment = NSTextAttachment()
            attachment.image = picture
            let scale = min(1, style.textWidth / picture.size.width)
            attachment.bounds = CGRect(
                x: 0, y: 0, width: picture.size.width * scale, height: picture.size.height * scale)
            let piece = NSMutableAttributedString(attachment: attachment)
            piece.addAttributes(attributes, range: NSRange(location: 0, length: piece.length))
            result.append(piece)
            return
        }
        var attributes = attributes
        attributes[.foregroundColor] = MarkdownColors.secondary
        if !source.isEmpty, attributes[.link] == nil { attributes[.link] = source }
        let font = attributes[.font] as? NSFont ?? style.bodyFont
        let description = node.plainText.isEmpty ? (source as NSString).lastPathComponent : node.plainText
        let piece = NSMutableAttributedString(
            attributedString: symbol("photo", description: "Image", font: font, color: MarkdownColors.secondary))
        piece.append(NSAttributedString(string: " " + description, attributes: attributes))
        piece.addAttributes(attributes, range: NSRange(location: 0, length: 1))
        result.append(piece)
    }

    /// `<br>` breaks the line, comments disappear, and other tags show as dimmed source.
    private func appendHTML(
        _ raw: String, to result: NSMutableAttributedString, attributes: [NSAttributedString.Key: Any]
    ) {
        let tag = raw.lowercased().replacingOccurrences(of: " ", with: "")
        if tag == "<br>" || tag == "<br/>" {
            result.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
            return
        }
        if raw.hasPrefix("<!--") { return }
        var attributes = attributes
        attributes[.foregroundColor] = MarkdownColors.secondary
        result.append(NSAttributedString(string: raw, attributes: attributes))
    }

    /// A task's box, ticked or not.
    func checkbox(checked: Bool) -> NSAttributedString {
        let font = style.bodyFont
        guard let picture = checked ? checkedBox : uncheckedBox else {
            return NSAttributedString(string: checked ? "☑" : "☐", attributes: [.font: font])
        }
        return Self.attachment(picture, centredIn: font)
    }

    /// An SF Symbol drawn in `color` at the size of text in `font`.
    static func symbolImage(_ name: String, description: String, font: NSFont, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
    }

    private func symbol(_ name: String, description: String, font: NSFont, color: NSColor) -> NSAttributedString {
        guard let picture = Self.symbolImage(name, description: description, font: font, color: color) else {
            return NSAttributedString(string: description, attributes: [.font: font, .foregroundColor: color])
        }
        return Self.attachment(picture, centredIn: font)
    }

    /// A picture that sits in a line of text in `font`, centred on its capital letters.
    private static func attachment(_ picture: NSImage, centredIn font: NSFont) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = picture
        attachment.bounds = CGRect(
            x: 0, y: (font.capHeight - picture.size.height) / 2, width: picture.size.width,
            height: picture.size.height)
        return NSAttributedString(attachment: attachment)
    }
}

extension NSFont {
    /// This font with `traits` added, such as bold inside a heading.
    func adding(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
