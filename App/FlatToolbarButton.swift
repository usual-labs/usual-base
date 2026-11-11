import AppKit
import SwiftUI

/// A toolbar button without glass: an icon on a 28 pt square that lights up under the pointer.
struct FlatIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.title3)
            // Gray, lighter than the toolbar's glass buttons.
            .foregroundStyle(isEnabled ? .secondary : .quaternary)
            .frame(width: 28, height: 28)
            .contentShape(.rect)
            .hoverHighlight(isPressed: configuration.isPressed)
    }
}

extension View {
    /// A rounded highlight behind the view while the pointer is over it, darker while pressed.
    /// `outset` widens it past the view without moving it, so text can keep its alignment.
    func hoverHighlight(isPressed: Bool = false, outset: CGFloat = 0) -> some View {
        modifier(HoverHighlight(isPressed: isPressed, outset: outset))
    }
}

private struct HoverHighlight: ViewModifier {
    let isPressed: Bool
    let outset: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let opacity = !isEnabled ? 0 : isPressed ? 0.14 : isHovered ? 0.08 : 0
        content
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(opacity))
                    .padding(.horizontal, -outset)
                    .frame(height: 28)
            }
            .onHover { isHovered = $0 }
            // `pointerStyle` has no effect in the toolbar, so the cursor is set directly.
            .onContinuousHover { phase in
                switch phase {
                case .active: (isEnabled ? NSCursor.pointingHand : .arrow).set()
                case .ended: NSCursor.arrow.set()
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
