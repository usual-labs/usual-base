import AppKit
import BaseKit
import SwiftUI

/// The document's Markdown source in a `MarkdownTextView`, with its properties card on top.
struct MarkdownEditor: NSViewRepresentable {
    let document: OpenDocument
    let openLink: (String) -> Void

    func makeCoordinator() -> EditorCoordinator { EditorCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)

        // Plain text in, plain text out: the file is Markdown, and agents read it byte for byte.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.allowedWritingToolsResultOptions = [.plainText]
        textView.typingAttributes = EditorTheme.base

        textView.delegate = context.coordinator
        textView.textLayoutManager?.delegate = context.coordinator
        context.coordinator.textView = textView
        return textView.inScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.show(document, openLink: openLink)
    }
}

@MainActor
final class EditorCoordinator: NSObject, NSTextViewDelegate, BodySource {
    weak var textView: MarkdownTextView?
    private var document: OpenDocument?
    private var loadedCount = -1
    private var editGeneration = 0
    private var styleTask: Task<Void, Never>?

    var currentBody: String { textView?.string ?? "" }

    func show(_ document: OpenDocument, openLink: @escaping (String) -> Void) {
        guard let textView else { return }
        textView.onOpenLink = openLink

        if document !== self.document || document.loadCount != loadedCount {
            let sameDocument = document === self.document
            let selection = textView.selectedRange()
            self.document?.editor = nil
            self.document = document
            document.editor = self
            loadedCount = document.loadCount
            editGeneration += 1
            styleTask?.cancel()

            textView.string = document.file.body
            textView.undoManager?.removeAllActions(withTarget: textView.textStorage as Any)
            // Style before the first draw so the text never flashes unstyled.
            if let storage = textView.textStorage {
                EditorTheme.apply(MarkdownHighlighter.spans(for: document.file.body), to: storage)
            }
            let length = (textView.string as NSString).length
            if sameDocument {
                let location = min(selection.location, length)
                textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            } else {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scroll(.zero)
            }
        }
        textView.showProperties(of: document, editable: true)
    }

    // MARK: - Editing

    func textDidChange(_ notification: Notification) {
        editGeneration += 1
        document?.bodyDidChange()
        scheduleStyle()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let textView = textView as? MarkdownTextView else { return false }
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        let edit: TextEdit?
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            edit = MarkdownEditing.newline(in: text, selection: selection)
        case #selector(NSResponder.insertTab(_:)):
            edit = MarkdownEditing.indent(in: text, selection: selection)
        case #selector(NSResponder.insertBacktab(_:)):
            edit = MarkdownEditing.outdent(in: text, selection: selection)
        default:
            edit = nil
        }
        guard let edit else { return false }
        textView.apply(edit)
        return true
    }

    /// Spelling marks only in prose: file names, paths and code aren't words.
    func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range: NSRange) -> Int {
        guard value != 0, let storage = textView.textStorage, range.length > 0, NSMaxRange(range) <= storage.length
        else { return value }
        return EditorTheme.isProse(at: range.location, in: storage) ? value : 0
    }

    func textViewWritingToolsDidEnd(_ textView: NSTextView) {
        scheduleStyle()
    }

    // MARK: - Styling

    /// Re-parses shortly after typing stops, off the main thread, and applies the result only
    /// if nothing changed in the meantime.
    private func scheduleStyle() {
        styleTask?.cancel()
        styleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, let self, let textView = self.textView else { return }
            // Restyling during input-method composition or Writing Tools would disturb them.
            if textView.hasMarkedText() || textView.isWritingToolsActive {
                self.scheduleStyle()
                return
            }
            let generation = self.editGeneration
            let text = textView.string
            let spans = await Task.detached(priority: .userInitiated) { MarkdownHighlighter.spans(for: text) }.value
            guard !Task.isCancelled, generation == self.editGeneration, let storage = textView.textStorage else {
                return
            }
            EditorTheme.apply(spans, to: storage)
            // Headings change size, which moves the selection under the bar.
            textView.formattingBarNeedsUpdate()
        }
    }
}

extension EditorCoordinator: NSTextLayoutManagerDelegate {
    nonisolated func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        if let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0,
            let name = paragraph.attributedString.attribute(.usualBlock, at: 0, effectiveRange: nil) as? String,
            let kind = BlockLayoutFragment.Kind(rawValue: name)
        {
            return BlockLayoutFragment(kind: kind, textElement: textElement, range: textElement.elementRange)
        }
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
