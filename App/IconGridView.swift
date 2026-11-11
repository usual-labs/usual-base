import AppKit

/// The sidebar's Icon menu: every folder icon in a grid, icons only, with their names as tooltips. A click picks
/// one and closes the menu.
final class IconGridView: NSView {
    private static let columns = 8
    private static let cell: CGFloat = 30
    private static let spacing: CGFloat = 2
    private static let padding: CGFloat = 8

    private let onPick: (String) -> Void

    init(selected: String, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        let choices = FileIcons.folderChoices
        let rows = (choices.count + Self.columns - 1) / Self.columns
        let step = Self.cell + Self.spacing
        let size = NSSize(
            width: 2 * Self.padding + CGFloat(Self.columns) * step - Self.spacing,
            height: 2 * Self.padding + CGFloat(rows) * step - Self.spacing)
        super.init(frame: NSRect(origin: .zero, size: size))
        for (index, choice) in choices.enumerated() {
            let button = IconGridButton(icon: choice.icon, title: choice.title, isChosen: choice.icon == selected)
            button.target = self
            button.action = #selector(picked(_:))
            let row = CGFloat(index / Self.columns)
            let column = CGFloat(index % Self.columns)
            button.frame = NSRect(
                x: Self.padding + column * step, y: size.height - Self.padding - Self.cell - row * step,
                width: Self.cell, height: Self.cell)
            addSubview(button)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel("Folder icon")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func picked(_ sender: IconGridButton) {
        onPick(sender.icon)
        var menu = enclosingMenuItem?.menu
        while let parent = menu?.supermenu { menu = parent }
        menu?.cancelTracking()
    }
}

/// One icon in the grid: lit under the pointer, tinted when it's the folder's current icon.
private final class IconGridButton: NSButton {
    let icon: String
    private let isChosen: Bool
    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    init(icon: String, title: String, isChosen: Bool) {
        self.icon = icon
        self.isChosen = isChosen
        super.init(frame: .zero)
        self.title = ""
        isBordered = false
        // An image view draws the symbol whole; the button's own image drawing clipped its edges.
        let image = NSImageView(image: NSImage(named: icon) ?? NSImage())
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        image.contentTintColor = isChosen ? SidebarColors.selectedText : .labelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = title
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // A menu's window is never key, so the area tracks always.
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    // Clicks on the icon belong to the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        if isChosen || isHovered {
            (isChosen ? SidebarColors.selection : SidebarColors.hover).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}
