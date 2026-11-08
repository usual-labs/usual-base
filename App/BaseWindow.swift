import AppKit
import SwiftUI

struct BaseWindow: View {
    @Environment(BaseModel.self) private var base

    var body: some View {
        @Bindable var base = base
        @Bindable var sync = base.sync
        NavigationSplitView {
            if base.root != nil {
                FileTreeView(tree: base.tree, selectedPath: base.document?.relativePath) { path in
                    base.openFile(path)
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            } else {
                Color.clear
            }
        } detail: {
            if let document = base.document {
                DocumentView(document: document)
            } else if base.root == nil {
                ContentUnavailableView {
                    Label("No Base Open", systemImage: "books.vertical")
                } description: {
                    Text("A Base is a folder of Markdown files that you and your agents share.")
                } actions: {
                    Button("Open Base…") { base.chooseBase() }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a file in the sidebar, or press ⌘P to find one.")
                )
            }
        }
        .navigationTitle(base.document?.name ?? base.name ?? "Usual Base")
        .navigationSubtitle(base.document == nil ? "" : base.name ?? "")
        .toolbar {
            ToolbarItemGroup {
                SyncStatusButton()
                Button {
                    base.isQuickOpenShown = true
                } label: {
                    Label("Quick Open", systemImage: "magnifyingglass")
                }
                .help("Find a file by name (⌘P)")
                .disabled(base.root == nil)
                Picker("Mode", selection: $base.mode) {
                    Text("View").tag(BaseModel.Mode.view)
                    Text("Edit").tag(BaseModel.Mode.edit)
                }
                .pickerStyle(.segmented)
                .help("View the rendered file, or edit its Markdown (⌘E)")
                .disabled(base.document == nil)
            }
        }
        .sheet(isPresented: $base.isQuickOpenShown) {
            QuickOpenView()
        }
        .sheet(isPresented: $sync.isSetupShown) {
            SyncSetupView()
        }
        .alert(
            base.problem ?? "",
            isPresented: Binding(get: { base.problem != nil }, set: { if !$0 { base.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
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
                    systemImage: "exclamationmark.triangle",
                    text:
                        "This file changed in two places at once. The other version is shown here; this Mac’s is saved as “\(copy.lastPathComponent)”."
                ) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([copy]) }
                    Button("Dismiss") { document.conflictCopy = nil }
                }
            }
            if document.isMissing {
                Notice(
                    systemImage: "trash",
                    text: "This file was moved or deleted. Editing it saves it again at the same place."
                ) {}
            }
            if let problem = document.problem {
                Notice(systemImage: "exclamationmark.octagon", text: problem) {
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
    let systemImage: String
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
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
