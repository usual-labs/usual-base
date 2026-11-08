#if DEBUG
    import AppKit

    /// For automated checks, which can't take screenshots without Screen Recording permission:
    /// `USUALBASE_SNAPSHOT=/path/shot.png` makes the app draw its window into that file shortly
    /// after launch (`USUALBASE_SNAPSHOT_DELAY` seconds, default 2.5).
    @MainActor
    enum DebugSnapshot {
        static func scheduleIfRequested() {
            let environment = ProcessInfo.processInfo.environment
            guard let path = environment["USUALBASE_SNAPSHOT"] else { return }
            let delay = Double(environment["USUALBASE_SNAPSHOT_DELAY"] ?? "") ?? 2.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
                // USUALBASE_SNAPSHOT_SIZE=1100x1200 resizes the window first, so more of a page fits.
                let size = environment["USUALBASE_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap { Double($0) }
                if let size, size.count == 2 { window.setContentSize(NSSize(width: size[0], height: size[1])) }
                // USUALBASE_SELECT=text selects its first match in the editor, which shows the formatting bar.
                if let wanted = environment["USUALBASE_SELECT"], let editor = find(MarkdownTextView.self, in: window) {
                    let range = (editor.string as NSString).range(of: wanted)
                    if range.location != NSNotFound {
                        window.makeFirstResponder(editor)
                        editor.setSelectedRange(range)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    guard let view = window.contentView?.superview ?? window.contentView,
                        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                    else { return }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
                }
            }
        }

        private static func find<View: NSView>(_ type: View.Type, in window: NSWindow) -> View? {
            var queue = window.contentView.map { [$0] } ?? []
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let match = view as? View { return match }
                queue += view.subviews
            }
            return nil
        }
    }
#endif
