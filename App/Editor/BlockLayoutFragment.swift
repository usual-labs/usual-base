import AppKit

/// Draws the full-width background behind code blocks and the bar beside quotes. TextKit 2
/// creates one fragment per paragraph (line), so adjacent code lines join into one block.
final class BlockLayoutFragment: NSTextLayoutFragment {
    enum Kind: String {
        case code, quote
    }

    let kind: Kind

    init(kind: Kind, textElement: NSTextElement, range: NSTextRange?) {
        self.kind = kind
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// The fragment's whole line, from the container's left edge, in the fragment's own coordinates.
    private var blockRect: CGRect {
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        return CGRect(x: -layoutFragmentFrame.minX, y: 0, width: width, height: layoutFragmentFrame.height)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(blockRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let rect = blockRect.offsetBy(dx: point.x, dy: point.y)
        context.saveGState()
        switch kind {
        case .code:
            context.setFillColor(EditorColors.codeBackground.cgColor)
            context.fill(rect)
        case .quote:
            context.setFillColor(EditorColors.quoteBar.cgColor)
            context.fill(CGRect(x: rect.minX + 2, y: rect.minY, width: 3, height: rect.height))
        }
        context.restoreGState()
        super.draw(at: point, in: context)
    }
}

/// Colours the fragment reads while drawing, which can happen off the main actor.
enum EditorColors {
    static var codeBackground: NSColor { .quaternarySystemFill }
    static var quoteBar: NSColor { .tertiaryLabelColor }
}
