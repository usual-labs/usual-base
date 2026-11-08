import BaseKit
import Foundation
import Observation

/// Where the editor's current text comes from when it's time to save.
@MainActor
protocol BodySource: AnyObject {
    var currentBody: String { get }
}

/// One Markdown file open in the editor. It saves shortly after each edit, and reloads when
/// something else (usually an agent) changes the file on disk.
@MainActor @Observable
final class OpenDocument {
    let url: URL
    let relativePath: String
    /// The file as last read or saved. The editor holds the newer body while it's dirty.
    private(set) var file: MarkdownFile
    private(set) var frontMatter: FrontMatter?
    /// Goes up each time the body is replaced from disk, which tells the editor to reload.
    private(set) var loadCount = 0
    private(set) var isDirty = false
    private(set) var isMissing = false
    /// Where this app's version went after a clash with a change on disk.
    var conflictCopy: URL?
    var problem: String?

    @ObservationIgnored weak var editor: (any BodySource)?
    @ObservationIgnored private var lastKnown: Data
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(root: URL, relativePath: String) throws {
        url = root.appending(path: relativePath)
        self.relativePath = relativePath
        let (file, data) = try DocumentStore.read(url)
        self.file = file
        lastKnown = data
        frontMatter = file.frontMatterYAML.map(FrontMatter.init(yaml:))
    }

    var name: String { url.lastPathComponent }

    func bodyDidChange() {
        if !isDirty { isDirty = true }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func updateFrontMatterYAML(_ yaml: String) {
        file = file.replacingFrontMatterYAML(yaml)
        frontMatter = file.frontMatterYAML.map(FrontMatter.init(yaml:))
        isDirty = true
        saveNow()
    }

    func saveNow() {
        saveTask?.cancel()
        guard isDirty else { return }
        var updated = file
        if let editor { updated.body = editor.currentBody }
        do {
            switch try DocumentStore.save(updated, to: url, lastKnown: lastKnown) {
            case .saved(let data):
                file = updated
                lastKnown = data
                isDirty = false
                isMissing = false
            case .conflict(let onDisk, let copy):
                conflictCopy = copy
                load(onDisk)
            }
        } catch {
            problem = "Couldn’t save “\(name)”: \(error.localizedDescription)"
        }
    }

    /// Called for every batch of file-system events in the Base. Reading one small file is
    /// cheaper than working out whether an event was about it.
    func checkDisk() {
        guard let data = try? Data(contentsOf: url) else {
            isMissing = !FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            return
        }
        isMissing = false
        guard data != lastKnown else { return }  // our own save, or nothing changed
        if isDirty {
            saveNow()  // the disk changed under unsaved edits: this ends in a conflict copy
        } else {
            load(data)
        }
    }

    private func load(_ data: Data) {
        guard let loaded = MarkdownFile(data: data) else {
            problem = "“\(name)” changed on disk and isn’t UTF-8 text any more."
            return
        }
        file = loaded
        lastKnown = data
        frontMatter = loaded.frontMatterYAML.map(FrontMatter.init(yaml:))
        isDirty = false
        loadCount += 1
    }
}
