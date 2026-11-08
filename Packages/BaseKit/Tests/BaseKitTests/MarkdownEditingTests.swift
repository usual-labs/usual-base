import Foundation
import Testing

@testable import BaseKit

@Suite struct MarkdownEditingTests {
    /// Applies an edit and marks the selection with `|` (caret) or `[` `]` (range).
    private func apply(_ edit: TextEdit?, to text: String) -> String? {
        guard let edit else { return nil }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        if edit.selection.length == 0 { return result.replacingCharacters(in: edit.selection, with: "|") }
        let marked = result.replacingCharacters(in: NSRange(location: NSMaxRange(edit.selection), length: 0), with: "]")
        return (marked as NSString).replacingCharacters(
            in: NSRange(location: edit.selection.location, length: 0), with: "[")
    }

    private func caret(_ text: String) -> (String, NSRange) {
        let location = (text as NSString).range(of: "|").location
        return (
            (text as NSString).replacingCharacters(in: NSRange(location: location, length: 1), with: ""),
            NSRange(location: location, length: 0)
        )
    }

    private func newline(_ marked: String) -> String? {
        let (text, selection) = caret(marked)
        return apply(MarkdownEditing.newline(in: text as NSString, selection: selection), to: text)
    }

    @Test func returnContinuesListsTasksAndQuotes() {
        #expect(newline("- item|") == "- item\n- |")
        #expect(newline("  * nested|") == "  * nested\n  * |")
        #expect(newline("9. ninth|\n") == "9. ninth\n10. |\n")
        #expect(newline("- [x] done|") == "- [x] done\n- [ ] |")
        #expect(newline("> quoted|") == "> quoted\n> |")
        #expect(newline("plain|") == nil)
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        #expect(newline("- one\n- |") == "- one\n|")
        #expect(newline("- [ ] |") == "|")
        #expect(newline("> |") == "|")
    }

    @Test func returnInsideTheMarkerDoesNothingSpecial() {
        #expect(newline("-| item") == nil)
    }

    @Test func returnKeepsCRLF() {
        #expect(newline("plain|\r\n") == "plain\r\n|\r\n")
        #expect(newline("- a|\r\n") == "- a\r\n- |\r\n")
    }

    @Test func tabNestsListLinesOnly() {
        let (text, selection) = caret("- a\n- b|")
        #expect(apply(MarkdownEditing.indent(in: text as NSString, selection: selection), to: text) == "- a\n  - b|")
        let (plain, plainSelection) = caret("plain|")
        #expect(MarkdownEditing.indent(in: plain as NSString, selection: plainSelection) == nil)
        let (nested, nestedSelection) = caret("1. a\n   1. |b")
        #expect(
            apply(MarkdownEditing.outdent(in: nested as NSString, selection: nestedSelection), to: nested)
                == "1. a\n1. |b")
    }

    @Test func linksWrapTheSelection() {
        let text = "read this" as NSString
        let this = NSRange(location: 5, length: 4)
        #expect(
            apply(MarkdownEditing.link(in: text, selection: this, url: nil), to: text as String) == "read [this](|)")
        #expect(
            apply(MarkdownEditing.link(in: text, selection: this, url: "https://usual.dev"), to: text as String)
                == "read [this](https://usual.dev)|")
        #expect(
            apply(
                MarkdownEditing.link(in: text, selection: NSRange(location: 0, length: 0), url: nil), to: text as String
            ) == "[|]()read this")
    }

    @Test func taskBoxesToggle() {
        let text = "- [ ] a\n- [X] b" as NSString
        let caretAtEnd = NSRange(location: text.length, length: 0)
        #expect(
            MarkdownEditing.toggleTask(in: text, box: NSRange(location: 2, length: 3), selection: caretAtEnd)?
                .replacement == "[x]")
        #expect(
            MarkdownEditing.toggleTask(in: text, box: NSRange(location: 10, length: 3), selection: caretAtEnd)?
                .replacement == "[ ]")
        #expect(
            MarkdownEditing.toggleTask(in: text, box: NSRange(location: 0, length: 3), selection: caretAtEnd) == nil)
    }
}
