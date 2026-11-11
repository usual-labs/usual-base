import AppKit
import BaseKit
import Observation

/// The open Base: its folder, the Markdown files in it, and the document being edited.
@MainActor @Observable
final class BaseModel {
    private(set) var root: URL?
    private(set) var paths: [String] = []
    private(set) var tree = FileNode.tree(from: [])
    private(set) var document: OpenDocument?
    let sync = SyncController()
    let sidebar = SidebarSettings()
    /// The hosted Usual Base account, whose Bases open from the sidebar's menu.
    let account = AccountModel()
    var isQuickOpenShown = false
    /// The wizard that makes a Base or puts one in a folder, shown in the card while it runs (`App/Setup/`).
    var setup: SetupFlow?
    /// View shows the open file rendered; Edit shows its Markdown source. The choice is remembered.
    var mode = Mode(rawValue: UserDefaults.standard.string(forKey: BaseModel.modeKey) ?? "") ?? .view {
        didSet {
            // The editor holds the newest text until it saves, and it goes away with Edit mode.
            if oldValue == .edit { document?.saveNow() }
            UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        }
    }
    /// A one-line message for the user, shown as an alert.
    var problem: String?

    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var rescanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanDelay: Task<Void, Never>?
    @ObservationIgnored private var accessedRoot: URL?
    /// The open hosted Base's live updates (`HostedBases.swift`).
    @ObservationIgnored var live: LiveUpdates?
    private static let bookmarkKey = "lastBaseBookmark"
    private static let modeKey = "documentMode"

    enum Mode: String {
        case view, edit
    }

    func toggleMode() {
        mode = mode == .view ? .edit : .view
    }

    var name: String? { root?.lastPathComponent }

    init() {
        sync.willSync = { [weak self] in self?.document?.saveNow() }
        sync.didFindConflicts = { [weak self] conflicts in self?.showConflicts(conflicts) }
        sync.fallbackCredentials = { [account] url in account.credentials(for: url) }
        sync.didChangeRemote = { [weak self] url in self?.remoteChanged(url) }
        account.didSignIn = { [weak self] in
            guard let self else { return }
            sync.reloadCredentials()
            remoteChanged(sync.remoteURL)
        }
    }

    // MARK: - Choosing a Base

    func chooseBase() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Base"
        panel.message = "Choose a folder of Markdown files."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rememberBookmark(for: url)
        open(url)
    }

    /// Reopens the folder from the last launch, if the sandbox still lets us.
    func restoreLastBase() {
        #if DEBUG
            // For automated runs, which can't use the folder picker. The sandbox only allows a
            // folder inside the app's container, such as ~/Library/Containers/<bundle id>/Data/…
            let environment = ProcessInfo.processInfo.environment
            if let mode = environment["USUALBASE_MODE"].flatMap(Mode.init) { self.mode = mode }
            if let value = environment["USUALBASE_SETUP"] {
                Task { await startDebugSetup(value) }
                return
            }
            if let path = environment["USUALBASE_OPEN"] {
                open(URL(filePath: path), file: environment["USUALBASE_FILE"])
                return
            }
        #endif
        guard root == nil, let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else { return }
        if isStale { rememberBookmark(for: url) }
        open(url)
    }

    func rememberBookmark(for url: URL) {
        let data = try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    func open(_ url: URL, file: String? = nil) {
        document?.saveNow()
        document = nil
        accessedRoot?.stopAccessingSecurityScopedResource()
        accessedRoot = url.startAccessingSecurityScopedResource() ? url : nil
        root = url
        sidebar.load(for: url)
        paths = []
        tree = FileNode.tree(from: [])
        watcher = FolderWatcher(folder: url) { [weak self] changed in
            Task { @MainActor in self?.filesChanged(changed) }
        }
        sync.open(url)
        rescan { [weak self] in
            guard let self, let last = file ?? UserDefaults.standard.string(forKey: self.lastFileKey),
                self.paths.contains(last)
            else { return }
            self.openFile(last)
        }
    }

    // MARK: - Files

    private func rescan(then completion: (@MainActor () -> Void)? = nil) {
        guard let root else { return }
        rescanTask?.cancel()
        rescanTask = Task {
            let paths = await Task.detached(priority: .userInitiated) { BaseIndex.scan(root) }.value
            let tree = await Task.detached(priority: .userInitiated) { FileNode.tree(from: paths) }.value
            guard !Task.isCancelled, root == self.root else { return }
            if paths != self.paths {
                self.paths = paths
                self.tree = tree
            }
            completion?()
        }
    }

    private func filesChanged(_ changed: [String]) {
        document?.checkDisk()
        // Git's own bookkeeping, including the sync's, isn't a change to publish.
        if changed.contains(where: { !$0.split(separator: "/").contains(".git") }) {
            sync.filesChanged()
        }
        // Hidden paths (like .git) never show, so their changes need no rescan.
        let relevant = changed.contains { path in
            !URL(filePath: path).pathComponents.contains { $0.hasPrefix(".") && $0.count > 1 }
        }
        guard relevant else { return }
        rescanDelay?.cancel()
        rescanDelay = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            rescan()
        }
    }

    /// Opens a Markdown file here; any other file opens in its own app.
    func openFile(_ relativePath: String) {
        guard let root, document?.relativePath != relativePath else { return }
        guard BaseIndex.isMarkdown(relativePath) else {
            NSWorkspace.shared.open(root.appending(path: relativePath))
            return
        }
        document?.saveNow()
        do {
            document = try OpenDocument(root: root, relativePath: relativePath)
            UserDefaults.standard.set(relativePath, forKey: lastFileKey)
        } catch DocumentStore.ReadError.notText {
            problem = "“\(relativePath)” isn’t UTF-8 text, so Usual Base can’t open it."
        } catch {
            problem = "Couldn’t open “\(relativePath)”: \(error.localizedDescription)"
        }
    }

    // MARK: - The open file's menu

    /// Renames the open file in its folder and keeps it open. Returns what went wrong, or nil.
    func renameDocument(to name: String) -> String? {
        guard let root, let document else { return nil }
        guard let path = FileNames.renaming(document.relativePath, to: name) else {
            return "A name can’t be empty, start with a dot, or contain “/” or “:”."
        }
        guard path != document.relativePath else { return nil }
        let target = root.appending(path: path)
        // A change of case alone is the same file to a case-insensitive disk.
        if path.lowercased() != document.relativePath.lowercased(),
            FileManager.default.fileExists(atPath: target.path(percentEncoded: false))
        {
            return "There’s already a file called “\(target.lastPathComponent)” in this folder."
        }
        document.saveNow()
        do {
            try FileManager.default.moveItem(at: document.url, to: target)
        } catch {
            return "Couldn’t rename “\(document.name)”: \(error.localizedDescription)"
        }
        sidebar.pathMoved(from: document.relativePath, to: path)
        self.document = nil
        openFile(path)
        rescan()
        return nil
    }

    /// Copies the open file next to it, as "Name copy.md", and opens the copy.
    func duplicateDocument() {
        guard let root, let document else { return }
        document.saveNow()
        let path = FileNames.copy(of: document.relativePath) {
            FileManager.default.fileExists(atPath: root.appending(path: $0).path(percentEncoded: false))
        }
        do {
            try FileManager.default.copyItem(at: document.url, to: root.appending(path: path))
        } catch {
            problem = "Couldn’t duplicate “\(document.name)”: \(error.localizedDescription)"
            return
        }
        rescan { [weak self] in self?.openFile(path) }
    }

    /// Moves the open file to the Trash, where it can be put back from.
    func trashDocument() {
        guard let document else { return }
        document.saveNow()
        do {
            try FileManager.default.trashItem(at: document.url, resultingItemURL: nil)
        } catch {
            problem = "Couldn’t move “\(document.name)” to the Trash: \(error.localizedDescription)"
            return
        }
        sidebar.pathRemoved(document.relativePath)
        self.document = nil
        UserDefaults.standard.removeObject(forKey: lastFileKey)
        rescan()
    }

    /// A sync kept the remote's version of the open file: say where this Mac's version went.
    private func showConflicts(_ conflicts: [SyncReport.Conflict]) {
        guard let root, let document, let conflict = conflicts.first(where: { $0.path == document.relativePath })
        else { return }
        document.conflictCopy = root.appending(path: conflict.copy)
    }

    private var lastFileKey: String { "lastFile:" + (root?.path(percentEncoded: false) ?? "") }

    /// A clicked link: Markdown files in this Base open here; web links and other files open in
    /// their usual app.
    func openLink(_ destination: String, from document: OpenDocument) {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.count > 1 {
            NSWorkspace.shared.open(url)
            return
        }
        guard let target = localTarget(of: trimmed, from: document) else { return }  // a heading in this file
        let path = pathInBase(of: target)
        guard FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            problem = "“\(path ?? target.lastPathComponent)” doesn’t exist."
            return
        }
        if let path, BaseIndex.markdownExtensions.contains(target.pathExtension.lowercased()) {
            openFile(path)
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    /// The picture an image in `document` shows, if it's a file in this Base. Pictures outside
    /// the Base and on the web aren't loaded.
    func image(at source: String, from document: OpenDocument) -> NSImage? {
        guard let target = localTarget(of: source, from: document), pathInBase(of: target) != nil else { return nil }
        return NSImage(contentsOf: target)
    }

    /// The file a link points to: relative to `document`, or to the Base for `/…`. Nil for web
    /// addresses and for links to a heading in the same file.
    private func localTarget(of destination: String, from document: OpenDocument) -> URL? {
        guard let root else { return nil }
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.count > 1 { return nil }
        let pathPart = String(trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let decoded = pathPart.removingPercentEncoding ?? pathPart
        guard !decoded.isEmpty else { return nil }
        let target =
            decoded.hasPrefix("/")
            ? root.appending(path: String(decoded.dropFirst()))
            : document.url.deletingLastPathComponent().appending(path: decoded)
        return target.standardizedFileURL
    }

    /// `url`'s path relative to the Base, or nil when it's outside the Base.
    private func pathInBase(of url: URL) -> String? {
        guard let root else { return nil }
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }
}
