import AppKit
import BaseKit
import SwiftUI

/// The open file rendered for reading: headings, lists, tables, code and pictures without their
/// Markdown syntax, with the properties card on top. Text can be selected, copied and found
/// (⌘F), and links open with a click.
///
/// It runs on TextKit 1 on purpose: only TextKit 1 lays out text tables (`NSTextTable`). The
/// editor stays on TextKit 2.
struct MarkdownViewer: NSViewRepresentable {
    let document: OpenDocument
    let image: (String) -> NSImage?
    let openLink: (String) -> Void

    func makeCoordinator() -> ViewerCoordinator { ViewerCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DocumentTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true  // so copied text keeps its formatting
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        return textView.inScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.show(document, image: image, openLink: openLink)
    }
}

@MainActor
final class ViewerCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: DocumentTextView?
    private var openLink: ((String) -> Void)?
    private var document: OpenDocument?
    private var renderedCount = -1

    /// Renders the document again when it's a different one or it changed on disk, keeping the
    /// scroll position for the same document.
    func show(_ document: OpenDocument, image: @escaping (String) -> NSImage?, openLink: @escaping (String) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        self.openLink = openLink
        if document !== self.document || document.loadCount != renderedCount {
            let sameDocument = document === self.document
            let origin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
            self.document = document
            renderedCount = document.loadCount
            let style = MarkdownRenderer.Style(
                bodyFont: EditorTheme.bodyFont, codeFont: EditorTheme.codeFont,
                textWidth: DocumentTextView.maxLineWidth)
            storage.setAttributedString(MarkdownRenderer.render(document.file.body, style: style, image: image))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(sameDocument ? origin : .zero)
        }
        textView.showProperties(of: document, editable: false)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let destination = (link as? String) ?? (link as? URL)?.absoluteString else { return false }
        openLink?(destination)
        return true
    }
}
