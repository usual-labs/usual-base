#if DEBUG
    import AppKit
    import ScreenCaptureKit

    /// A passive, opt-in review feed. The separate loopback server serves this one atomic file.
    /// It has no input, file-editing or sync commands. Release contains none of this code.
    @MainActor
    final class DebugReview {
        private let folder: URL
        private var task: Task<Void, Never>?

        private init(folder: URL) { self.folder = folder }

        static func startIfRequested() -> DebugReview? {
            guard let path = ProcessInfo.processInfo.environment["USUALBASE_REVIEW"], path.hasPrefix("/") else {
                return nil
            }
            let review = DebugReview(folder: URL(filePath: path))
            do {
                try FileManager.default.createDirectory(
                    at: review.folder, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                try Data("\(ProcessInfo.processInfo.processIdentifier)".utf8)
                    .write(to: review.folder.appending(path: "pid"), options: .atomic)
            } catch {
                NSLog("Review could not start: %@", error.localizedDescription)
                return nil
            }
            review.task = Task { [weak review] in
                while !Task.isCancelled {
                    if let review, FileManager.default.fileExists(atPath: review.folder.appending(path: "stop").path) {
                        NSApp.terminate(nil)
                        break
                    }
                    await review?.capture()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            return review
        }

        func stop() { task?.cancel() }

        private func capture() async {
            // Prefer sheets/panels while they are visible, otherwise the main document window.
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
                window.isVisible, !window.isMiniaturized,
                let root = window.contentView?.superview
            else { return }
            let frame = window.frame
            let before = ReviewTree.elements(in: window, root: root)
            var captureKind = "Window capture"
            var warning: String?
            let bitmap: NSBitmapImageRep
            do {
                let content = try await SCShareableContent.currentProcess
                guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
                else { throw ReviewError.windowUnavailable }
                let filter = SCContentFilter(desktopIndependentWindow: target)
                let config = SCStreamConfiguration()
                let scale = min(2, 2560 / max(frame.width, 1))
                config.width = Int((frame.width * scale).rounded())
                config.height = Int((frame.height * scale).rounded())
                config.scalesToFit = true
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                bitmap = NSBitmapImageRep(cgImage: image)
            } catch {
                // Never substitute a stale screenshot, or pretend cacheDisplay renders real glass.
                guard let fallback = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
                root.cacheDisplay(in: root.bounds, to: fallback)
                bitmap = fallback
                captureKind = "Approximate preview"
                warning = "Glass and focus effects may differ. Window capture failed: \(error.localizedDescription)"
            }
            guard !Task.isCancelled, window.isVisible, frame == window.frame,
                before == ReviewTree.elements(in: window, root: root),
                let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
            else { return }
            let snapshot = ReviewSnapshot(
                capturedAt: Date().timeIntervalSince1970, window: window.windowNumber,
                title: window.title, width: frame.width, height: frame.height,
                image: "data:image/jpeg;base64," + jpeg.base64EncodedString(),
                captureKind: captureKind, warning: warning, elements: before)
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: folder.appending(path: "snapshot.json"), options: .atomic)
            } catch {
                NSLog("Review could not write its frame: %@", error.localizedDescription)
            }
        }

        private enum ReviewError: Error { case windowUnavailable }
    }

    private struct ReviewSnapshot: Encodable {
        let capturedAt: Double
        let window: Int
        let title: String
        let width: Double
        let height: Double
        let image: String
        let captureKind: String
        let warning: String?
        let elements: [ReviewTree.Element]
    }

    @MainActor
    private enum ReviewTree {
        struct Element: Encodable, Equatable {
            let id: String
            let parent: String?
            let label: String
            let className: String
            let role: String
            let path: String
            let depth: Int
            let x: Double
            let y: Double
            let width: Double
            let height: Double
            let named: Bool
        }

        static func elements(in window: NSWindow, root: NSView) -> [Element] {
            var result: [Element] = []
            func visit(_ view: NSView, parent: String?, path: String, depth: Int) {
                guard result.count < 2000, depth < 40, !view.isHidden, view.alphaValue > 0 else { return }
                // Unclipped AppKit views can report a visibleRect larger than their own bounds.
                let visible = view.bounds.intersection(view.visibleRect)
                let rect = window.convertToScreen(view.convert(visible, to: nil)).intersection(window.frame)
                guard !rect.isNull, rect.width > 1, rect.height > 1 else { return }
                let className = String(describing: type(of: view))
                let id = String(describing: ObjectIdentifier(view))
                let label = label(for: view)
                let ownPath = path.isEmpty ? className : path + " / " + className
                result.append(
                    Element(
                        id: id, parent: parent, label: label, className: className,
                        role: view.accessibilityRole()?.rawValue ?? "view", path: ownPath, depth: depth,
                        x: rect.minX - window.frame.minX, y: window.frame.maxY - rect.maxY,
                        width: rect.width, height: rect.height, named: view is ReviewMarkerView))
                for child in view.subviews { visit(child, parent: id, path: ownPath, depth: depth + 1) }
            }
            visit(root, parent: nil, path: "", depth: 0)
            return result
        }

        private static func label(for view: NSView) -> String {
            if let marker = view as? ReviewMarkerView { return marker.name }
            if view is NSSecureTextField { return "Secure field" }
            if let text = view as? DocumentTextView {
                return text is MarkdownTextView ? "Markdown editor" : "Rendered document"
            }
            if let cell = view as? NSTableCellView, let text = cell.textField { return text.stringValue }
            if let label = view.accessibilityLabel(), !label.isEmpty { return String(label.prefix(120)) }
            if let tip = view.toolTip, !tip.isEmpty { return String(tip.prefix(120)) }
            if let button = view as? NSButton, !button.title.isEmpty { return String(button.title.prefix(120)) }
            if let text = view as? NSTextField, !text.isEditable { return String(text.stringValue.prefix(120)) }
            if view is NSOutlineView { return "Files and folders" }
            if view is NSScrollView { return "Scroll area" }
            return String(describing: type(of: view))
        }
    }
#endif
