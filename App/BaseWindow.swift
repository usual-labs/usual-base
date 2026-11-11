import AppKit
import SwiftUI

struct BaseWindow: View {
    @Environment(BaseModel.self) private var base
    @SceneStorage("sidebarVisible") private var sidebarVisible = true
    @AppStorage("historyVisible") private var historyVisible = false
    @AppStorage("sidebarWidth") private var sidebarWidth = 240.0
    @AppStorage("historyWidth") private var historyWidth = 260.0

    /// The gap around the document's card, which is also where the panes are resized.
    private static let gap: CGFloat = 8
    /// How far the toolbar puts the title from the window's leading edge, and the mode button's trailing edge from
    /// the window's trailing edge, with no gap, measured in a window capture. The toolbar doesn't know where the
    /// card is, so gaps of the remaining width line the title and the mode button up with the card's edges.
    private static let titleStart: CGFloat = 128
    private static let buttonsWidth: CGFloat = 115
    /// Half white in light mode; in Dark Mode mostly black, since a lighter tint turns the card a light gray.
    private static let cardTint = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.black.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.5)
        })
    /// How the side panes open and close.
    static let paneAnimation = Animation.smooth(duration: 0.3)

    var body: some View {
        @Bindable var base = base
        @Bindable var sync = base.sync
        // The panes sit straight on the window's glass, with the document on a glass card
        // between them. A split view would draw divider lines across the glass, so the gaps
        // beside the card resize the panes instead.
        HStack(spacing: 0) {
            SidePane(isShown: sidebarVisible, width: sidebarWidth, edge: .leading) {
                VStack(spacing: 0) {
                    BaseSwitcher()
                    if base.root != nil {
                        FileTreeView(
                            tree: base.tree, title: base.name ?? "Files", selectedPath: base.document?.relativePath,
                            favorites: base.sidebar.favorites, folderIcons: base.sidebar.folderIcons, root: base.root,
                            settings: base.sidebar
                        ) { path in
                            base.openFile(path)
                        }
                    } else {
                        Color.clear
                    }
                }
            }
            PaneResizer(width: $sidebarWidth, range: 180...400, growsRightward: true)
                .frame(width: Self.gap)
                .disabled(!sidebarVisible)
            // The document's card is a layer of Liquid Glass over the window's glass, tinted toward the
            // text background (white, or near black in Dark Mode) so text reads over anything behind it.
            detail
                .animation(.smooth(duration: 0.3), value: base.setup.map(ObjectIdentifier.init))
                .clipShape(.rect(cornerRadius: 12))
                .glassEffect(.regular.tint(Self.cardTint), in: .rect(cornerRadius: 12))
                .frame(minWidth: 360, maxWidth: .infinity)
                .padding(.bottom, Self.gap)
                .layoutPriority(1)
            PaneResizer(width: $historyWidth, range: 220...420, growsRightward: false)
                .frame(width: Self.gap)
                .disabled(!historyVisible)
            SidePane(isShown: historyVisible, width: historyWidth, edge: .trailing) {
                HistoryPane(isShown: historyVisible)
                    .reviewElement("History")
            }
        }
        .animation(Self.paneAnimation, value: sidebarVisible)
        .animation(Self.paneAnimation, value: historyVisible)
        .navigationTitle(base.document?.name ?? base.name ?? "Usual Base")
        // The toolbar shows the name as the file's menu instead (`FileTitleMenu`).
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            // Each gap shares an item with the control before it: the toolbar gives even an empty item
            // 44 pt, and a gap inside an item can close to nothing as its pane slides shut.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 0) {
                    Button {
                        sidebarVisible.toggle()
                    } label: {
                        Label(sidebarVisible ? "Hide Sidebar" : "Show Sidebar", image: "lucide.panel-left")
                    }
                    .buttonStyle(FlatIconButtonStyle())
                    .frame(height: 28)
                    .help(sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                    .keyboardShortcut("s", modifiers: [.control, .command])
                    .reviewElement("Show / Hide Sidebar")
                    ToolbarGap(width: cardLeading - Self.titleStart)
                        .animation(Self.paneAnimation, value: sidebarVisible)
                    FileTitleMenu()
                        .padding(.leading, 8)
                        .reviewElement("File menu")
                }
            }
            .sharedBackgroundVisibility(.hidden)
            // Without the system title, nothing else pushes the rest to the trailing edge.
            ToolbarSpacer(.flexible)
            ToolbarItem {
                HStack(spacing: 0) {
                    // One flat button that shows what a click switches to, like the View menu's command.
                    Button {
                        base.toggleMode()
                    } label: {
                        if base.mode == .view {
                            Label("Edit Markdown", image: "lucide.pencil")
                        } else {
                            Label("View Rendered", image: "lucide.eye")
                        }
                    }
                    .buttonStyle(FlatIconButtonStyle())
                    .frame(height: 28)
                    .help(base.mode == .view ? "Edit the Markdown (⌘E)" : "View the rendered file (⌘E)")
                    .disabled(base.document == nil)
                    .reviewElement("View / Edit mode")
                    ToolbarGap(width: cardTrailing - Self.buttonsWidth)
                        .animation(Self.paneAnimation, value: historyVisible)
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                HStack(spacing: 4) {
                    Button {
                        historyVisible.toggle()
                    } label: {
                        Label(historyVisible ? "Hide History" : "Show History", image: "lucide.panel-right")
                    }
                    .help(historyVisible ? "Hide the file’s history" : "Show who changed this file, and when")
                    .keyboardShortcut("h", modifiers: [.control, .command])
                    .reviewElement("Show / Hide History")
                    SyncStatusButton()
                        .reviewElement("Sync status and settings")
                    Button {
                        base.isQuickOpenShown = true
                    } label: {
                        Label("Quick Open", image: "lucide.search")
                    }
                    .help("Find a file by name (⌘P)")
                    .disabled(base.root == nil)
                    .reviewElement("Quick Open")
                }
                .buttonStyle(FlatIconButtonStyle())
                .frame(height: 28)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $base.isQuickOpenShown) {
            QuickOpenView()
        }
        .sheet(isPresented: $sync.isSetupShown) {
            SyncSetupView()
        }
        .sheet(
            isPresented: Binding(
                // The setup wizard shows the code itself.
                get: { if case .signingIn = base.account.state { base.setup == nil } else { false } },
                set: { if !$0, case .signingIn = base.account.state { base.account.cancelSignIn() } })
        ) {
            if case .signingIn(let code, let url) = base.account.state {
                SignInSheet(account: base.account, code: code, url: url)
            }
        }
        .alert(
            base.account.problem ?? "",
            isPresented: Binding(
                get: { base.account.problem != nil }, set: { if !$0 { base.account.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
        .alert(
            base.problem ?? "",
            isPresented: Binding(get: { base.problem != nil }, set: { if !$0 { base.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Where the card starts from the window's leading edge, and ends from its trailing edge.
    private var cardLeading: CGFloat { (sidebarVisible ? sidebarWidth : 0) + Self.gap }
    private var cardTrailing: CGFloat { (historyVisible ? historyWidth : 0) + Self.gap }

    @ViewBuilder
    private var detail: some View {
        if let setup = base.setup {
            SetupWizard(flow: setup)
                .transition(.opacity)
        } else if let document = base.document {
            DocumentView(document: document)
        } else if base.root == nil {
            WelcomeView()
                .transition(.opacity)
        } else {
            ContentUnavailableView(
                "No File Selected",
                image: "lucide.file-text",
                description: Text("Choose a file in the sidebar, or press ⌘P to find one.")
            )
        }
    }
}

/// The open file: notices about it, then the file rendered or its source, by mode.
struct DocumentView: View {
    @Environment(BaseModel.self) private var base
    let document: OpenDocument

    var body: some View {
        VStack(spacing: 0) {
            if let copy = document.conflictCopy {
                Notice(
                    image: "lucide.triangle-alert",
                    text:
                        "This file changed in two places at once. The other version is shown here; this Mac’s is saved as “\(copy.lastPathComponent)”."
                ) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([copy]) }
                    Button("Dismiss") { document.conflictCopy = nil }
                }
            }
            if document.isMissing {
                Notice(
                    image: "lucide.trash-2",
                    text: "This file was moved or deleted. Editing it saves it again at the same place."
                ) {}
            }
            if let problem = document.problem {
                Notice(image: "lucide.octagon-alert", text: problem) {
                    Button("Dismiss") { document.problem = nil }
                }
            }
            switch base.mode {
            case .view:
                MarkdownViewer(
                    document: document,
                    image: { base.image(at: $0, from: document) },
                    openLink: { base.openLink($0, from: document) }
                )
            case .edit:
                MarkdownEditor(document: document) { destination in
                    base.openLink(destination, from: document)
                }
            }
        }
    }
}

private struct Notice<Actions: View>: View {
    let image: String
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(image)
                .foregroundStyle(.orange)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}

/// The gap beside a pane: dragging it resizes the pane, like a split view's divider without the line.
private struct PaneResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// True for a pane on the left, which grows as the gap moves right.
    let growsRightward: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .pointerStyle(isEnabled ? .columnResize : nil)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        let change = growsRightward ? drag.translation.width : -drag.translation.width
                        width = min(max(start + change, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil },
                isEnabled: isEnabled
            )
    }
}

/// Empty space in the toolbar, which moves the items after it. It opens and closes with its pane,
/// a step per animation frame.
private struct ToolbarGap: View, @preconcurrency Animatable {
    var width: CGFloat

    init(width: CGFloat) {
        self.width = max(width, 0)
    }

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    var body: some View {
        GapView.Representable(width: width)
            .frame(width: width, height: 1)
    }
}

/// Tells the toolbar when the gap's width changes. The toolbar measures a SwiftUI item once and
/// keeps that slot; it measures again only when the item's view says its size changed, which
/// SwiftUI doesn't.
private final class GapView: NSView {
    struct Representable: NSViewRepresentable {
        let width: CGFloat
        func makeNSView(context: Context) -> GapView { GapView() }
        func updateNSView(_ view: GapView, context: Context) { view.width = width }
    }

    var width: CGFloat = 0 {
        didSet {
            guard width != oldValue else { return }
            invalidateIntrinsicContentSize()
            // The item's view is the nearest ancestor below the toolbar's own item viewer.
            var ancestor = superview
            while let view = ancestor, !NSStringFromClass(type(of: view)).contains("ToolbarItemViewer") {
                view.invalidateIntrinsicContentSize()
                ancestor = view.superview
            }
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: 1) }

    override func isAccessibilityElement() -> Bool { false }
}

/// A pane beside the card that slides and blurs in and out. It keeps its width while the space for it
/// opens or closes, so its contents slide rather than squeeze, and it stays alive while hidden,
/// so the file tree keeps its open folders and scroll position.
private struct SidePane<Content: View>: View {
    let isShown: Bool
    let width: Double
    let edge: HorizontalEdge
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: width)
            .frame(width: isShown ? width : 0, alignment: edge == .leading ? .trailing : .leading)
            .clipped()
            // A blur reveal: the pane comes into focus as it opens and goes out of focus as it closes.
            .blur(radius: isShown ? 0 : 12)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }
}
