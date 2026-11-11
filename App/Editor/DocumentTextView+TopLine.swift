import AppKit

/// The text at the top of the visible part of the view, so a view that changes width can show
/// the same text afterwards.
struct TopLine {
    /// The UTF-16 offset where the top line's paragraph or line fragment starts, or nil when
    /// the view shows the space above the text (the top padding or the properties card).
    var location: Int?
    /// How far the visible part starts below that fragment's top; for nil, the scroll offset.
    var offset: CGFloat
}

extension DocumentTextView {
    func topLine() -> TopLine? {
        guard let clip = enclosingScrollView?.contentView, !visibleRect.isEmpty else { return nil }
        // The clip view, not `visibleRect`: at the very top it starts above the view, in the
        // scroll view's inset, and a resize would otherwise scroll it down to zero.
        let top = clip.bounds.minY - textContainerOrigin.y
        guard top > 0 else { return TopLine(location: nil, offset: clip.bounds.minY) }
        if let layout = textLayoutManager, let content = layout.textContentManager {
            guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: top)) else { return nil }
            let location = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            return TopLine(location: location, offset: top - fragment.layoutFragmentFrame.minY)
        }
        // Only the viewer gets here: it's TextKit 1. The editor's `layoutManager` must never be
        // touched (AGENTS.md).
        guard let layout = layoutManager, let container = textContainer else { return nil }
        let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: top), in: container)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return TopLine(location: layout.characterIndexForGlyph(at: glyph), offset: top - line.minY)
    }

    /// Scrolls so `line` is back at the top, after the text was laid out again.
    func scroll(toTopLine line: TopLine) {
        guard let location = line.location else {
            guard let scrollView = enclosingScrollView else { return }
            // Within the scroll range: an offset from a moment ago may lie past the new top.
            let clip = scrollView.contentView
            var bounds = clip.bounds
            bounds.origin.y = line.offset
            clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(clip)
            return
        }
        let fragmentTop: CGFloat
        let fragmentHeight: CGFloat
        if let layout = textLayoutManager, let content = layout.textContentManager {
            guard let location = content.location(content.documentRange.location, offsetBy: location),
                let range = NSTextRange(location: location, end: location)
            else { return }
            layout.ensureLayout(for: range)
            guard let fragment = layout.textLayoutFragment(for: location) else { return }
            fragmentTop = fragment.layoutFragmentFrame.minY
            fragmentHeight = fragment.layoutFragmentFrame.height
        } else if let layout = layoutManager {
            let length = (string as NSString).length
            guard length > 0 else { return }
            let glyph = layout.glyphIndexForCharacter(at: min(location, length - 1))
            layout.ensureLayout(forGlyphRange: NSRange(location: 0, length: glyph + 1))
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            fragmentTop = rect.minY
            fragmentHeight = rect.height
        } else {
            return
        }
        let y = textContainerOrigin.y + fragmentTop + min(line.offset, fragmentHeight)
        scroll(NSPoint(x: 0, y: y))
    }
}
