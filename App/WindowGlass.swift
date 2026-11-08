import AppKit
import SwiftUI

/// Frosted glass behind the whole window: the desktop and the windows behind show through,
/// blurred. It stays translucent when the app isn't active; SwiftUI's materials turn opaque
/// then. With Reduce Transparency on, AppKit draws it opaque.
struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
