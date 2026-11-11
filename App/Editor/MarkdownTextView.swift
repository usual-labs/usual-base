import AppKit
import BaseKit

/// The Markdown editor's text view: Apple's NSTextView on TextKit 2, plus clickable task boxes
/// and links, link paste, the format commands and the formatting bar over selected text.
///
/// Never touch this view's `layoutManager`: asking for it silently and permanently switches
/// the view to TextKit 1, which loses the block drawing and inline Writing Tools.
final class MarkdownTextView: DocumentTextView {
    var onOpenLink: ((String) -> Void)?
    private lazy var formattingBar = FormattingBar { [weak self] in self?.format($0) }
    private var formattingBarUpdateIsQueued = false
    private var cursorIsOverBar = false

    // MARK: - Clicks

    // Over the formatting bar, its cursor instead of the I-beam; back on the text, the I-beam again, since the
    // text view only resets it on entering.
    override func mouseMoved(with event: NSEvent) {
        if let cursor = formattingBar.cursor(at: event.locationInWindow) {
            cursor.set()
            cursorIsOverBar = true
        } else {
            if cursorIsOverBar { NSCursor.iBeam.set() }
            cursorIsOverBar = false
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if let cursor = formattingBar.cursor(at: event.locationInWindow) {
            cursor.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let storage = textStorage {
            // The insertion point can fall on either side of the character that was clicked.
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                var box = NSRange()
                if isEditable, storage.attribute(.usualTaskBox, at: candidate, effectiveRange: &box) != nil,
                    let edit = MarkdownEditing.toggleTask(
                        in: storage.string as NSString, box: box, selection: selectedRange())
                {
                    apply(edit)
                    return
                }
                let wantsLink = event.modifierFlags.contains(.command) || !isEditable
                if wantsLink,
                    let destination = storage.attribute(.usualLink, at: candidate, effectiveRange: nil) as? String
                {
                    onOpenLink?(destination)
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: - Editing

    /// Makes one undoable change, the way typing would.
    func apply(_ edit: TextEdit) {
        guard isEditable, shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        scrollRangeToVisible(edit.selection)
    }

    /// Runs a Format command, from the menu or the formatting bar.
    func format(_ format: MarkdownFormat) {
        let url = format == .link ? NSPasteboard.general.string(forType: .string).flatMap(Self.webURL) : nil
        guard isEditable,
            let edit = MarkdownEditing.toggle(format, in: string as NSString, selection: selectedRange(), url: url)
        else {
            NSSound.beep()
            return
        }
        apply(edit)
        undoManager?.setActionName(format.title)
    }

    /// Pasting a web address over selected text makes a link instead of replacing the text.
    override func paste(_ sender: Any?) {
        if selectedRange().length > 0, let url = NSPasteboard.general.string(forType: .string).flatMap(Self.webURL) {
            apply(MarkdownEditing.link(in: string as NSString, selection: selectedRange(), url: url))
            return
        }
        super.paste(sender)
    }

    private static func webURL(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil
        else { return nil }
        return trimmed
    }

    // MARK: - Formatting bar

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        // The bar waits until a drag-selection ends.
        if stillSelectingFlag {
            formattingBar.isHidden = true
        } else {
            formattingBarNeedsUpdate()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { formattingBarNeedsUpdate() }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { formattingBar.isHidden = true }
        return resigned
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !formattingBar.isHidden { formattingBarNeedsUpdate() }
    }

    /// Places the bar again once the current event is handled, after the text has moved or the
    /// selection changed.
    func formattingBarNeedsUpdate() {
        guard !formattingBarUpdateIsQueued else { return }
        formattingBarUpdateIsQueued = true
        Task { @MainActor [weak self] in
            self?.formattingBarUpdateIsQueued = false
            self?.updateFormattingBar()
        }
    }

    /// Shows the bar just above the visible part of the selection, or below it when there's no
    /// room above, or hides it when nothing is selected.
    private func updateFormattingBar() {
        let selection = selectedRange()
        guard isEditable, selection.length > 0, window?.firstResponder === self, !hasMarkedText(),
            !isWritingToolsActive, let selected = visibleSelectionRect()
        else {
            formattingBar.isHidden = true
            return
        }
        // Checking every format reads every selected line, so a huge selection shows none lit.
        let text = string as NSString
        let checksStates = selection.length <= 20_000
        formattingBar.showStates { checksStates && MarkdownEditing.isApplied($0, in: text, selection: selection) }

        if formattingBar.superview == nil { addSubview(formattingBar) }
        let size = formattingBar.preferredSize
        let visible = visibleRect
        var origin = NSPoint(x: selected.midX - size.width / 2, y: selected.minY - size.height - 6)
        if origin.y < visible.minY + 4 { origin.y = selected.maxY + 6 }
        if origin.y + size.height > visible.maxY - 4 { origin.y = visible.minY + 8 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        formattingBar.frame = NSRect(origin: origin, size: size)
        formattingBar.isHidden = false
    }

    /// The selection's on-screen part, in this view's coordinates.
    private func visibleSelectionRect() -> NSRect? {
        guard let layout = textLayoutManager, let content = layout.textContentManager,
            let viewport = layout.textViewportLayoutController.viewportRange
        else { return nil }
        let selection = selectedRange()
        guard let start = content.location(content.documentRange.location, offsetBy: selection.location),
            let end = content.location(start, offsetBy: selection.length),
            let shown = NSTextRange(location: start, end: end)?.intersection(viewport)
        else { return nil }
        var union = NSRect.null
        layout.enumerateTextSegments(in: shown, type: .selection, options: .rangeNotRequired) { _, frame, _, _ in
            union = union.union(frame)
            return true
        }
        let origin = textContainerOrigin
        let rect = union.offsetBy(dx: origin.x, dy: origin.y).intersection(visibleRect)
        return rect.isNull ? nil : rect
    }
}
