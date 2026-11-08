import AppKit
import BaseKit

/// The bar that floats over selected text in the editor. Its buttons run the Format menu's
/// commands, and light up for formats the selection already has.
final class FormattingBar: NSView {
    private static let inlineFormats: [MarkdownFormat] = [.bold, .italic, .strikethrough, .code, .link]
    private static let lineFormats: [MarkdownFormat] = [.bulletList, .numberedList, .taskList, .quote]
    private static let headingLevels = [1, 2, 3, 0]

    private let onFormat: (MarkdownFormat) -> Void
    private let row = NSStackView()
    private let glass = NSGlassEffectView()
    private let headings = NSPopUpButton(frame: .zero, pullsDown: true)
    private var buttons: [(format: MarkdownFormat, button: NSButton)] = []

    init(onFormat: @escaping (MarkdownFormat) -> Void) {
        self.onFormat = onFormat
        super.init(frame: .zero)
        row.orientation = .horizontal
        row.spacing = 1
        row.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        for format in Self.inlineFormats { row.addArrangedSubview(makeButton(format)) }
        row.addArrangedSubview(makeHeadingMenu())
        for format in Self.lineFormats { row.addArrangedSubview(makeButton(format)) }
        if let link = buttons.last(where: { $0.format == .link })?.button { row.setCustomSpacing(10, after: link) }
        row.setCustomSpacing(10, after: headings)

        glass.contentView = row
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Format")
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The size that fits every button.
    var preferredSize: NSSize { row.fittingSize }

    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = bounds.height / 2
    }

    /// Lights up the buttons for the formats the selection has.
    func showStates(_ isApplied: (MarkdownFormat) -> Bool) {
        for (format, button) in buttons {
            button.contentTintColor = isApplied(format) ? .controlAccentColor : nil
        }
        var hasHeading = false
        for item in headings.itemArray.dropFirst() {
            let applied = isApplied(.heading(item.tag))
            item.state = applied ? .on : .off
            if applied, item.tag > 0 { hasHeading = true }
        }
        headings.contentTintColor = hasHeading ? .controlAccentColor : nil
    }

    // Clicks between the buttons stay in the bar instead of reaching the text below.
    override func mouseDown(with event: NSEvent) {}

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    // MARK: - Controls

    private func makeButton(_ format: MarkdownFormat) -> NSButton {
        let button = NSButton(image: Self.symbol(format) ?? NSImage(), target: self, action: #selector(pressed(_:)))
        style(button)
        button.toolTip = format.title
        button.setAccessibilityLabel(format.title)
        button.tag = buttons.count
        buttons.append((format, button))
        return button
    }

    private func makeHeadingMenu() -> NSPopUpButton {
        style(headings)
        (headings.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        headings.toolTip = "Heading"
        headings.setAccessibilityLabel("Heading")
        // A pull-down button shows its first item, so that item is the button's face.
        headings.addItem(withTitle: "")
        headings.item(at: 0)?.image = Self.symbol(.heading(1))
        for level in Self.headingLevels {
            let item = NSMenuItem(
                title: MarkdownFormat.heading(level).title, action: #selector(headingChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level
            headings.menu?.addItem(item)
        }
        return headings
    }

    private func style(_ button: NSButton) {
        // Plain icons on the glass; a lit format shows in the accent colour.
        button.isBordered = false
        button.imagePosition = .imageOnly
        // The text view keeps the keyboard focus and its selection.
        button.refusesFirstResponder = true
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private static func symbol(_ format: MarkdownFormat) -> NSImage? {
        NSImage(systemSymbolName: format.symbolName, accessibilityDescription: format.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
    }

    @objc private func pressed(_ sender: NSButton) {
        onFormat(buttons[sender.tag].format)
    }

    @objc private func headingChosen(_ sender: NSMenuItem) {
        onFormat(.heading(sender.tag))
    }
}

extension MarkdownFormat {
    /// The name in the Format menu, the bar's tooltips and Undo.
    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .code: "Code"
        case .link: "Link"
        case .heading(let level): level > 0 ? "Heading \(level)" : "Body Text"
        case .bulletList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .taskList: "Task List"
        case .quote: "Quote"
        }
    }

    var symbolName: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .heading: "textformat.size"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .taskList: "checklist"
        case .quote: "text.quote"
        }
    }
}
