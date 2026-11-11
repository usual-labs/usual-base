import SwiftUI

extension View {
    /// Names SwiftUI-drawn controls that don't have their own inspectable NSView.
    /// The marker exists only in an explicitly requested Debug review session.
    @ViewBuilder
    func reviewElement(_ name: String) -> some View {
        #if DEBUG
            if ProcessInfo.processInfo.environment["USUALBASE_REVIEW"] != nil {
                background(ReviewMarker(name: name).allowsHitTesting(false).accessibilityHidden(true))
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if DEBUG
    private struct ReviewMarker: NSViewRepresentable {
        let name: String

        func makeNSView(context: Context) -> ReviewMarkerView { ReviewMarkerView() }

        func updateNSView(_ view: ReviewMarkerView, context: Context) { view.name = name }
    }

    final class ReviewMarkerView: NSView {
        var name = ""

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
#endif
