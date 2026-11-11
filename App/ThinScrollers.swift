import AppKit
import SwiftUI

/// The app's scroll bar: thin, light, and shown only while scrolling, whatever the "Show scroll bars" setting.
/// The solid bar the setting can choose looks heavy on the glass.
final class ThinScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        contentView.drawsBackground = false
        Self.makeThin(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // The system sets every scroll view's style again when the setting changes; this one stays overlay.
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    static func makeThin(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
    }
}

extension View {
    /// Gives the SwiftUI `ScrollView` this sits in the app's thin scroll bar. Put it on the scroll view's content.
    func thinScrollers() -> some View {
        background(ThinScrollersAnchor())
    }
}

private struct ThinScrollersAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) { view.apply() }

    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // The system resets the style when the "Show scroll bars" setting changes.
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(
                self, selector: #selector(apply), name: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil)
        }

        @objc func apply() {
            if let scrollView = enclosingScrollView { ThinScrollView.makeThin(scrollView) }
        }
    }
}
