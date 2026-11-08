import AppKit
import SwiftUI

/// A text view for one document, in a scroll view: the text sits at a readable width in the
/// middle, with room at the top for the properties card. The editor and the viewer both use it.
class DocumentTextView: NSTextView {
    static let maxLineWidth: CGFloat = 720
    private static let minSidePadding: CGFloat = 28
    private static let topPadding: CGFloat = 22

    private var card: NSHostingView<AnyView>?
    private var cardHeight: CGFloat = 0

    /// A scroll view holding this text view, which grows with its text and wraps at the view's width.
    func inScrollView() -> NSScrollView {
        autoresizingMask = [.width]
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
        // The window's glass shows through behind the text.
        drawsBackground = false

        let scrollView = NSScrollView()
        scrollView.documentView = self
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutChrome()
    }

    /// Centres the text at a readable width and keeps the card above it.
    private func layoutChrome() {
        let side = max(Self.minSidePadding, (bounds.width - Self.maxLineWidth) / 2)
        let top = Self.topPadding + (cardHeight > 0 ? cardHeight + 18 : 0)
        let inset = NSSize(width: side, height: top)
        if textContainerInset != inset { textContainerInset = inset }
        card?.frame = NSRect(x: side, y: Self.topPadding, width: max(bounds.width - 2 * side, 0), height: cardHeight)
    }

    /// The document's front matter as a card above the text, or no card when it has none.
    func showProperties(of document: OpenDocument, editable: Bool) {
        guard let frontMatter = document.frontMatter, let yaml = document.file.frontMatterYAML else {
            setCard(Optional<PropertiesCard>.none)
            return
        }
        setCard(
            PropertiesCard(frontMatter: frontMatter, yaml: yaml, isReading: !editable) { [weak document] newYAML in
                document?.updateFrontMatterYAML(newYAML)
            }
        )
    }

    /// Shows a view above the text that scrolls with it, or removes it when `view` is nil.
    private func setCard<Content: View>(_ view: Content?) {
        guard let view else {
            card?.removeFromSuperview()
            card = nil
            cardHeight = 0
            layoutChrome()
            return
        }
        let measured = AnyView(
            view
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { [weak self] height in
                    self?.cardHeightChanged(height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
        if let card {
            card.rootView = measured
        } else {
            let host = NSHostingView(rootView: measured)
            host.sizingOptions = []
            addSubview(host)
            card = host
            // Measure against a tall frame first; the real height comes back from SwiftUI.
            cardHeight = 1
            layoutChrome()
            host.frame.size.height = 2000
        }
    }

    private func cardHeightChanged(_ height: CGFloat) {
        let rounded = ceil(height)
        guard rounded != cardHeight, card != nil else { return }
        cardHeight = rounded
        layoutChrome()
    }
}
