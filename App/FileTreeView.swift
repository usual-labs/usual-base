import AppKit
import BaseKit
import SwiftUI

/// The Base's folders and Markdown files in an `NSOutlineView`, which only builds the rows
/// on screen, so thousands of files stay fast.
struct FileTreeView: NSViewRepresentable {
    let tree: FileNode
    let selectedPath: String?
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.allowsMultipleSelection = false
        outline.autoresizesOutlineColumn = true
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        context.coordinator.outline = outline

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.update(tree: tree, selectedPath: selectedPath)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        weak var outline: NSOutlineView?
        var onSelect: ((String) -> Void)?
        private var tree = FileNode.tree(from: [])
        private var isSelectingProgrammatically = false

        func update(tree newTree: FileNode, selectedPath: String?) {
            guard let outline else { return }
            if newTree !== tree {
                // Keep open folders open across rescans.
                let expanded = expandedPaths()
                tree = newTree
                outline.reloadData()
                expand(tree, paths: expanded)
            }
            select(selectedPath)
        }

        private func expandedPaths() -> Set<String> {
            guard let outline else { return [] }
            var paths: Set<String> = []
            for row in 0..<outline.numberOfRows {
                if let node = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(node) {
                    paths.insert(node.path)
                }
            }
            return paths
        }

        private func expand(_ node: FileNode, paths: Set<String>) {
            for child in node.children where child.isFolder && paths.contains(child.path) {
                outline?.expandItem(child)
                expand(child, paths: paths)
            }
        }

        private func select(_ path: String?) {
            guard let outline else { return }
            let current = (outline.item(atRow: outline.selectedRow) as? FileNode)?.path
            guard current != path else { return }
            isSelectingProgrammatically = true
            defer { isSelectingProgrammatically = false }
            guard let path, let node = node(at: path) else {
                outline.deselectAll(nil)
                return
            }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return }
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }

        /// Finds a file's node, expanding the folders on the way so it has a row.
        private func node(at path: String) -> FileNode? {
            var node = tree
            for component in path.split(separator: "/") {
                guard let child = node.children.first(where: { $0.name == component }) else { return nil }
                if child.isFolder { outline?.expandItem(child) }
                node = child
            }
            return node
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            ((item as? FileNode) ?? tree).children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? FileNode) ?? tree).children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.isFolder ?? false
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("cell")
            let cell =
                outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? makeCell(identifier)
            cell.textField?.stringValue = node.isFolder ? node.name : (node.name as NSString).deletingPathExtension
            cell.textField?.toolTip = node.path
            cell.imageView?.image = NSImage(
                systemSymbolName: node.isFolder ? "folder" : "doc.text",
                accessibilityDescription: node.isFolder ? "Folder" : "File"
            )
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSelectingProgrammatically, let outline,
                let node = outline.item(atRow: outline.selectedRow) as? FileNode, !node.isFolder
            else { return }
            onSelect?(node.path)
        }

        private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            for view in [image, text] as [NSView] {
                view.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(view)
            }
            cell.imageView = image
            cell.textField = text
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }
}
