import AppKit
import BaseKit
import SwiftUI

/// The sidebar: Favorites, then the Base's folders and files, in an `NSOutlineView`, which only builds the rows on
/// screen, so thousands of files stay fast. Markdown files are selected and open here; a click on a folder opens or
/// closes it, and other files open in their own app.
struct FileTreeView: NSViewRepresentable {
    let tree: FileNode
    let title: String
    let selectedPath: String?
    let favorites: [String]
    let folderIcons: [String: String]
    let root: URL?
    let settings: SidebarSettings
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = SidebarOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        // Plain, not a source list: a source list lays its own selection view over the row, and the rows draw
        // their own selection, hover and insets (`SidebarRowView`).
        outline.style = .plain
        outline.rowSizeStyle = .custom
        outline.indentationPerLevel = 16
        outline.backgroundColor = .clear
        outline.allowsMultipleSelection = false
        // The one column always fills the sidebar's width, so a row's highlight ends inside it; deep rows
        // truncate their names instead of widening the outline.
        outline.autoresizesOutlineColumn = false
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        column.resizingMask = .autoresizingMask
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.target = context.coordinator
        outline.action = #selector(Coordinator.clicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outline.menu = menu
        context.coordinator.outline = outline

        let scrollView = ThinScrollView()
        scrollView.documentView = outline
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        weak var outline: NSOutlineView?
        private var onSelect: ((String) -> Void)?
        private var settings: SidebarSettings?
        private var root: URL?
        private var tree = FileNode.tree(from: [])
        private var favoritePaths: [String] = []
        private var favorites: [FavoriteItem] = []
        private var folderIcons: [String: String] = [:]
        private let favoritesHeading = SidebarSection(title: "Favorites", icon: "lucide.star")
        private let filesHeading = SidebarSection(title: "", icon: "lucide.library")
        /// The top level: each heading, then its rows. Headings are dividers, not folders, so their rows aren't
        /// indented under them.
        private var topItems: [Any] = []
        private var isSelectingProgrammatically = false
        /// The open document, which the selection shows whenever its row is visible.
        private var selectedPath: String?
        /// Closing a folder that holds the selected row moves the selection to another row; that isn't a choice.
        private var isCollapsing = false

        func update(_ view: FileTreeView) {
            guard let outline else { return }
            onSelect = view.onSelect
            settings = view.settings
            root = view.root
            if view.tree !== tree || view.favorites != favoritePaths || view.folderIcons != folderIcons
                || view.title != filesHeading.title
            {
                // Keep open folders open across rescans.
                let expanded = expandedPaths()
                tree = view.tree
                favoritePaths = view.favorites
                folderIcons = view.folderIcons
                filesHeading.title = view.title
                favorites = view.favorites.compactMap { node(at: $0, expanding: false).map(FavoriteItem.init) }
                let favoriteRows: [Any] = favorites.isEmpty ? [] : [favoritesHeading] + favorites
                topItems = favoriteRows + [filesHeading] + tree.children
                outline.reloadData()
                expand(tree, paths: expanded)
            }
            selectedPath = view.selectedPath
            select(view.selectedPath)
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
            guard let outline, self.path(of: outline.item(atRow: outline.selectedRow)) != path else { return }
            isSelectingProgrammatically = true
            defer { isSelectingProgrammatically = false }
            guard let path, let node = node(at: path, expanding: true) else {
                outline.deselectAll(nil)
                return
            }
            let row = outline.row(forItem: node)
            guard row >= 0 else {
                outline.deselectAll(nil)
                return
            }
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }

        /// Finds a file's or folder's node; `expanding` opens the folders on the way (and a folder itself) so it
        /// has a row.
        private func node(at path: String, expanding: Bool) -> FileNode? {
            var node = tree
            for component in path.split(separator: "/") {
                guard let child = node.children.first(where: { $0.name == component }) else { return nil }
                if expanding, child.isFolder { outline?.expandItem(child) }
                node = child
            }
            return node === tree ? nil : node
        }

        private func path(of item: Any?) -> String? {
            fileNode(of: item)?.path
        }

        private func fileNode(of item: Any?) -> FileNode? {
            (item as? FileNode) ?? (item as? FavoriteItem)?.node
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            switch item {
            case nil: topItems.count
            case let node as FileNode: node.children.count
            default: 0
            }
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            switch item {
            case nil: topItems[index]
            case let node as FileNode: node.children[index]
            default: tree
            }
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode)?.isFolder == true
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            if let section = item as? SidebarSection {
                let cell =
                    outlineView.makeView(withIdentifier: FileCell.headerIdentifier, owner: nil) as? FileCell
                    ?? FileCell(header: true)
                cell.configure(name: section.title, icon: section.icon)
                return cell
            }
            guard let node = fileNode(of: item) else { return nil }
            let cell =
                outlineView.makeView(withIdentifier: FileCell.rowIdentifier, owner: nil) as? FileCell
                ?? FileCell(header: false)
            let showsExtension = node.isFolder || !BaseIndex.isMarkdown(node.name)
            cell.configure(
                name: showsExtension ? node.name : (node.name as NSString).deletingPathExtension,
                icon: node.isFolder ? FileIcons.folder(chosen: folderIcons[node.path]) : FileIcons.file(node.name),
                iconDescription: node.isFolder ? "Folder" : "File",
                toolTip: node.path)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            item is SidebarSection ? 34 : 28
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let row = SidebarRowView()
            row.showsHover = !(item is SidebarSection)
            return row
        }

        // Only Markdown files are selected: the selection is the open document.
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let node = fileNode(of: item) else { return false }
            return !node.isFolder && BaseIndex.isMarkdown(node.name)
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSelectingProgrammatically, !isCollapsing, let outline,
                let path = path(of: outline.item(atRow: outline.selectedRow))
            else { return }
            onSelect?(path)
        }

        func outlineViewItemWillCollapse(_ notification: Notification) {
            isCollapsing = true
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            isCollapsing = false
            // The open document stays selected if its row still shows; otherwise nothing is.
            guard let outline else { return }
            isSelectingProgrammatically = true
            defer { isSelectingProgrammatically = false }
            let row = selectedPath.flatMap { node(at: $0, expanding: false) }.map { outline.row(forItem: $0) } ?? -1
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                outline.deselectAll(nil)
            }
        }

        /// Folders open or close; a favorite folder shows in the tree; other files open in their app.
        @objc func clicked(_ outline: NSOutlineView) {
            let item = outline.item(atRow: outline.clickedRow)
            if (item as? FileNode)?.isFolder == true {
                toggle(item)
            } else if let favorite = item as? FavoriteItem, favorite.node.isFolder {
                reveal(favorite.node.path)
            } else if let node = fileNode(of: item), !BaseIndex.isMarkdown(node.name) {
                onSelect?(node.path)
            }
        }

        private func toggle(_ item: Any?) {
            guard let outline else { return }
            if outline.isItemExpanded(item) {
                outline.animator().collapseItem(item)
            } else {
                outline.animator().expandItem(item)
            }
        }

        private func reveal(_ path: String) {
            guard let outline else { return }
            guard let node = node(at: path, expanding: true) else { return }
            let row = outline.row(forItem: node)
            if row >= 0 { outline.scrollRowToVisible(row) }
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, let settings, let node = fileNode(of: outline.item(atRow: outline.clickedRow)) else {
                return
            }
            let title = settings.isFavorite(node.path) ? "Remove from Favorites" : "Add to Favorites"
            menu.addItem(item(title, #selector(toggleFavorite(_:)), node.path))
            if node.isFolder {
                let grid = NSMenuItem()
                let path = node.path
                grid.view = IconGridView(selected: FileIcons.folder(chosen: folderIcons[path])) {
                    [weak settings] icon in
                    settings?.setIcon(icon, forFolder: path)
                }
                let icons = NSMenu()
                icons.addItem(grid)
                let iconItem = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
                iconItem.submenu = icons
                menu.addItem(iconItem)
            }
            menu.addItem(.separator())
            menu.addItem(item("Show in Finder", #selector(showInFinder(_:)), node.path))
        }

        func menuWillOpen(_ menu: NSMenu) {
            guard menu === outline?.menu, let outline, outline.clickedRow >= 0 else { return }
            (outline.rowView(atRow: outline.clickedRow, makeIfNecessary: false) as? SidebarRowView)?.isMenuTarget = true
        }

        func menuDidClose(_ menu: NSMenu) {
            guard menu === outline?.menu, let outline else { return }
            outline.enumerateAvailableRowViews { row, _ in (row as? SidebarRowView)?.isMenuTarget = false }
        }

        private func item(_ title: String, _ action: Selector, _ value: Any) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            return item
        }

        @objc private func toggleFavorite(_ sender: NSMenuItem) {
            guard let path = sender.representedObject as? String else { return }
            settings?.toggleFavorite(path)
        }

        @objc private func showInFinder(_ sender: NSMenuItem) {
            guard let root, let path = sender.representedObject as? String else { return }
            NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: path)])
        }
    }
}
