import AppKit
import SwiftUI

/// The open file's name in the toolbar, as a flat button that opens the file's menu.
struct FileTitleMenu: View {
    @Environment(BaseModel.self) private var base
    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        let document = base.document
        Menu {
            Button("Rename…") {
                newName = document.map { ($0.name as NSString).deletingPathExtension } ?? ""
                isRenaming = true
            }
            Button("Duplicate") { base.duplicateDocument() }
            Divider()
            Button("Show in Finder") {
                if let url = document?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(document?.relativePath ?? "", forType: .string)
            }
            Divider()
            Button("Move to Trash", role: .destructive) { base.trashDocument() }
        } label: {
            // One text, so the chevron stays after the name: a menu puts a separate image first.
            Text("\(document?.name ?? base.name ?? "Usual Base")  \(Image("lucide.chevron-right"))")
                .font(.headline)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Flat, as tall as the toolbar's buttons.
        .frame(height: 28)
        .contentShape(.rect)
        // The highlight reaches past the name, so the name itself stays lined up with the card.
        .hoverHighlight(outset: 8)
        .disabled(document == nil)
        .help(document.map { "\($0.relativePath): rename, duplicate, show in Finder, or move to the Trash" } ?? "")
        .alert("Rename “\(document?.name ?? "")”", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let problem = base.renameDocument(to: newName) { base.problem = problem }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file keeps its place in the folder. Links to its old name in other notes don’t change.")
        }
    }
}
