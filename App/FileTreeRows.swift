import AppKit
import BaseKit

/// A divider with a title in the sidebar, above Favorites or the Base's files.
final class SidebarSection {
    var title: String
    let icon: String

    init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }
}

/// A row in Favorites. Its own object, since the outline view needs every row's item to be unique and the same
/// file or folder also has a row in the tree.
final class FavoriteItem {
    let node: FileNode
    init(node: FileNode) { self.node = node }
}

/// The sidebar's colours: quiet text, and a selection in a soft tint of the accent colour, with the selected
/// row's text in the accent colour instead of white.
enum SidebarColors {
    static let text = NSColor.labelColor
    static let header = NSColor.secondaryLabelColor
    static let hover = NSColor.labelColor.withAlphaComponent(0.07)
    static let selectedText = dynamic { isDark in
        isDark ? accent.blended(withFraction: 0.35, of: .white) ?? accent : accent
    }
    static let selection = dynamic { isDark in accent.withAlphaComponent(isDark ? 0.22 : 0.14) }

    private static var accent: NSColor { NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue }

    private static func dynamic(_ make: @escaping @Sendable (Bool) -> NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            var color = NSColor.clear
            appearance.performAsCurrentDrawingAppearance {
                color = make(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
            }
            return color
        }
    }
}

/// A section heading, or a file or folder with its icon.
final class FileCell: NSTableCellView {
    static let headerIdentifier = NSUserInterfaceItemIdentifier("header")
    static let rowIdentifier = NSUserInterfaceItemIdentifier("row")

    private let isHeader: Bool
    var isSelectedRow = false {
        didSet { if isSelectedRow != oldValue { applyColors() } }
    }

    init(header: Bool) {
        isHeader = header
        super.init(frame: .zero)
        identifier = header ? Self.headerIdentifier : Self.rowIdentifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.font = header ? .systemFont(ofSize: 11, weight: .semibold) : .systemFont(ofSize: 13)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        textField = text
        var constraints = [
            // Headings sit low in their taller row, so a new section starts with a gap above it.
            text.centerYAnchor.constraint(equalTo: centerYAnchor, constant: header ? 4 : 0)
        ]
        if header {
            // A divider: the title, then a hairline to the row's end.
            let line = NSBox()
            line.boxType = .custom
            line.borderWidth = 0
            line.fillColor = .separatorColor
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            text.setContentHuggingPriority(.required, for: .horizontal)
            let image = NSImageView()
            image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
            imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: text.centerYAnchor),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
                line.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 8),
                line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                line.centerYAnchor.constraint(equalTo: text.centerYAnchor),
                line.heightAnchor.constraint(equalToConstant: 1),
            ]
        } else {
            constraints.append(text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4))
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
            imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(name: String, icon: String? = nil, iconDescription: String? = nil, toolTip: String? = nil) {
        textField?.stringValue = name
        textField?.toolTip = toolTip
        if let icon {
            let image = NSImage(named: icon)
            image?.accessibilityDescription = iconDescription
            imageView?.image = image
        }
    }

    private func applyColors() {
        let color = isHeader ? SidebarColors.header : isSelectedRow ? SidebarColors.selectedText : SidebarColors.text
        textField?.textColor = color
        imageView?.contentTintColor = color
    }
}

/// A row that lights up under the pointer, and draws the selection itself so the selected row keeps readable,
/// accent-coloured text instead of white on a solid accent.
final class SidebarRowView: NSTableRowView {
    var showsHover = true
    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    /// The row a right-click menu is open for, ringed in the accent colour.
    var isMenuTarget = false {
        didSet { if isMenuTarget != oldValue { needsDisplay = true } }
    }

    override var isSelected: Bool {
        didSet { for case let cell as FileCell in subviews { cell.isSelectedRow = isSelected } }
    }

    // Never emphasized: an emphasized source-list row draws a solid accent selection itself instead of calling
    // `drawSelection`, and its cells switch to white text.
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? FileCell)?.isSelectedRow = isSelected
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        // A row reused while scrolling, or one that scrolled out from under the pointer, rechecks.
        if let window {
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            isHovered = window.isKeyWindow && bounds.contains(point)
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if showsHover, isHovered, !isSelected {
            SidebarColors.hover.setFill()
            shape.fill()
        }
        if isMenuTarget {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 11, dy: 2), xRadius: 5, yRadius: 5)
            ring.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        SidebarColors.selection.setFill()
        shape.fill()
    }

    private var shape: NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 1), xRadius: 6, yRadius: 6)
    }
}

/// An outline with a leading margin, so the chevrons and rows sit inside the rounded highlight that
/// `SidebarRowView` draws 10 pt in from each side. A plain outline has no margin of its own.
final class SidebarOutlineView: NSOutlineView {
    private static let margin: CGFloat = 10

    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        super.frameOfOutlineCell(atRow: row).offsetBy(dx: Self.margin, dy: 0)
    }

    /// How much closer a row's icon sits to its chevron than the outline would put it.
    private static let chevronGap: CGFloat = 6

    // Each row's content runs to the highlight's trailing edge, so names use the whole width before truncating.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        // A divider starts at the margin, with no room kept for a chevron.
        frame.origin.x = item(atRow: row) is SidebarSection ? Self.margin : frame.minX + Self.margin - Self.chevronGap
        frame.size.width = max(bounds.width - Self.margin - frame.minX, 0)
        return frame
    }

    // The table's own right-click ring is square and spans the row; `SidebarRowView` draws a rounded one.
    @objc(drawContextMenuHighlightForRow:)
    func drawContextMenuHighlight(forRow row: Int) {}
}
