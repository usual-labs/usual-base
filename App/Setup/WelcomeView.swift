import AppKit
import SwiftUI

/// The card when no Base is open: make a Base, put one you have in a folder, or open any folder of notes.
struct WelcomeView: View {
    @Environment(BaseModel.self) private var base

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                Text("Welcome to Usual Base")
                    .font(.system(size: 26, weight: .semibold))
                Text("A Base is a folder of Markdown notes that you and your agents share.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 14) {
                ChoiceCard(
                    image: "lucide.library", title: "Create a Base",
                    text: "Start a new Base for a project, a team or your own notes, synced with Usual Base."
                ) { base.startSetup(.create) }
                ChoiceCard(
                    image: "lucide.link", title: "Connect a Base to a folder",
                    text: "Put a Base you already have on this Mac: with your other Bases, or inside a project."
                ) { base.startSetup(.connect) }
            }
            .frame(maxWidth: 580)
            Button("Open a folder of notes on this Mac…") { base.chooseBase() }
                .buttonStyle(.link)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A large choice with an icon, a title and a sentence, lit up under the pointer.
struct ChoiceCard: View {
    let image: String
    let title: String
    let text: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(image)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 9))
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(ChoiceCardStyle(isSelected: isSelected))
    }
}

struct ChoiceCardStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        CardBody(label: configuration.label, isPressed: configuration.isPressed, isSelected: isSelected)
    }

    private struct CardBody: View {
        let label: Configuration.Label
        let isPressed: Bool
        let isSelected: Bool
        @State private var isHovered = false

        var body: some View {
            label
                .background(
                    .primary.opacity(isPressed ? 0.1 : isHovered || isSelected ? 0.07 : 0.035),
                    in: .rect(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isSelected ? Color.accentColor : .primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                }
                .scaleEffect(isPressed ? 0.985 : 1)
                .onHover { isHovered = $0 }
                .animation(.smooth(duration: 0.18), value: isHovered)
                .animation(.smooth(duration: 0.12), value: isPressed)
        }
    }
}
