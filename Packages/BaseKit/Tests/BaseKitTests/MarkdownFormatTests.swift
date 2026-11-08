import Foundation
import Testing

@testable import BaseKit

/// Text is marked with `«` `»` around the selection, or `|` for a caret.
@Suite struct MarkdownFormatTests {
    private func parse(_ marked: String) -> (NSString, NSRange) {
        let text = marked as NSString
        let caret = text.range(of: "|")
        if caret.location != NSNotFound {
            return (
                text.replacingCharacters(in: caret, with: "") as NSString, NSRange(location: caret.location, length: 0)
            )
        }
        let start = text.range(of: "«").location
        let end = text.range(of: "»").location
        let plain = (text.replacingOccurrences(of: "«", with: "") as NSString).replacingOccurrences(of: "»", with: "")
        return (plain as NSString, NSRange(location: start, length: end - start - 1))
    }

    private func mark(_ text: NSString, _ selection: NSRange) -> String {
        if selection.length == 0 { return text.replacingCharacters(in: selection, with: "|") }
        let end = text.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "»")
        return (end as NSString).replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "«")
    }

    private func toggle(_ format: MarkdownFormat, _ marked: String, url: String? = nil) -> String? {
        let (text, selection) = parse(marked)
        guard let edit = MarkdownEditing.toggle(format, in: text, selection: selection, url: url) else { return nil }
        return mark(text.replacingCharacters(in: edit.range, with: edit.replacement) as NSString, edit.selection)
    }

    private func has(_ format: MarkdownFormat, _ marked: String) -> Bool {
        let (text, selection) = parse(marked)
        return MarkdownEditing.isApplied(format, in: text, selection: selection)
    }

    @Test func boldAndItalicWrapAndUnwrap() {
        #expect(toggle(.bold, "a «word» here") == "a **«word»** here")
        #expect(toggle(.bold, "a **«word»** here") == "a «word» here")
        #expect(toggle(.bold, "a «**word**» here") == "a «word» here")
        #expect(toggle(.bold, "a __«word»__ here") == "a «word» here")
        // Italic on bold adds to it instead of eating one star of the bold, and back again.
        #expect(toggle(.italic, "a **«word»** here") == "a ***«word»*** here")
        #expect(toggle(.italic, "a ***«word»*** here") == "a **«word»** here")
        #expect(toggle(.bold, "a ***«word»*** here") == "a *«word»* here")
        #expect(toggle(.italic, "a |word") == "a *|*word")
        #expect(toggle(.bold, "a **|** b") == "a | b")
        #expect(toggle(.bold, "«é😀»") == "**«é😀»**")
    }

    @Test func inlineFormatsSkipMarkersAndSpaces() {
        #expect(toggle(.bold, "«- one\n»two") == "- **«one»**\n" + "two")
        #expect(toggle(.italic, "«## Title  »") == "## *«Title»*  ")
        #expect(toggle(.bold, "«- [ ] task»") == "- [ ] **«task»**")
        #expect(toggle(.bold, "«   »") == nil)
    }

    @Test func inlineFormatsWrapEachLine() {
        #expect(toggle(.bold, "«- one\n- two»") == "- **«one**\n- **two»**")
        #expect(toggle(.bold, "«- **one**\n- two»") == "- **«one**\n- **two»**")
        #expect(toggle(.bold, "«- **one**\n\n- **two**»") == "- «one\n\n- two»")
        #expect(toggle(.code, "«one\r\ntwo»") == "`«one`\r\n`two»`")
    }

    @Test func formatsNestAndComeOffInAnyOrder() {
        #expect(toggle(.strikethrough, "**«x»**") == "**~~«x»~~**")
        #expect(toggle(.strikethrough, "~~**«x»**~~") == "**«x»**")
        #expect(toggle(.bold, "~~**«x»**~~") == "~~«x»~~")
        #expect(toggle(.italic, "**_«x»_**") == "**«x»**")
        #expect(toggle(.code, "«x»") == "`«x»`")
        #expect(toggle(.code, "`«x»`") == "«x»")
        // Markers inside code would show as text, so bold goes outside it.
        #expect(toggle(.bold, "`«x»`") == "**`«x»`**")
    }

    @Test func appliedFormatsAreReported() {
        #expect(has(.bold, "**«x»**"))
        #expect(!has(.italic, "**«x»**"))
        #expect(has(.italic, "«***x***»"))
        #expect(has(.bold, "«***x***»"))
        #expect(!has(.bold, "«- **one**\n- two»"))
        #expect(has(.strikethrough, "~~«gone»~~ and"))
        #expect(has(.link, "see [«this»](https://usual.dev)"))
        #expect(!has(.link, "![«alt»](a.png)"))
        #expect(has(.heading(2), "## «Title»"))
        #expect(has(.heading(0), "«plain»"))
        #expect(has(.bulletList, "«- a\n\n- b»"))
        #expect(!has(.bulletList, "«- [ ] a»"))
        #expect(has(.taskList, "«- [ ] a\n1. [x] b»"))
        #expect(has(.quote, "«> a\n>\n> b»"))
    }

    @Test func linksWrapTheTrimmedSelectionAndComeOff() {
        #expect(toggle(.link, "read «this »now", url: "https://usual.dev") == "read [this](https://usual.dev)| now")
        #expect(toggle(.link, "«- item»") == "- [item](|)")
        #expect(toggle(.link, "read [«this»](https://usual.dev) now") == "read «this» now")
        #expect(toggle(.link, "read «[this](https://usual.dev)» now") == "read «this» now")
    }

    @Test func headingsReplaceTheLineMarker() {
        #expect(toggle(.heading(2), "|Title") == "## |Title")
        #expect(toggle(.heading(2), "## Ti|tle") == "Ti|tle")
        #expect(toggle(.heading(1), "## Title|") == "# Title|")
        #expect(toggle(.heading(1), "- «item»") == "# «item»")
        #expect(toggle(.heading(0), "### |Title") == "|Title")
        #expect(toggle(.heading(0), "|Title") == nil)
        #expect(toggle(.heading(3), "> |quoted") == "> ### |quoted")
    }

    @Test func listsAndTasksToggleEveryLine() {
        #expect(toggle(.bulletList, "«one\ntwo»") == "«- one\n- two»")
        #expect(toggle(.bulletList, "«- one\n- two»") == "«one\ntwo»")
        #expect(toggle(.bulletList, "«1. one\n## two»") == "«- one\n- two»")
        #expect(toggle(.bulletList, "|") == "- |")
        #expect(toggle(.numberedList, "«one\n\ntwo»") == "«1. one\n\n2. two»")
        #expect(toggle(.numberedList, "«- a\n  - b\n  - c\n- d\n  - e»") == "«1. a\n  1. b\n  2. c\n2. d\n  1. e»")
        #expect(toggle(.taskList, "«- a\nb\n3. c»") == "«- [ ] a\n- [ ] b\n3. [ ] c»")
        #expect(toggle(.taskList, "«- [x] a\n- [ ] b»") == "«a\nb»")
        #expect(toggle(.taskList, "«- [x] a\nb»") == "«- [x] a\n- [ ] b»")
    }

    @Test func lineFormatsKeepLineEndingsAndTheLineAfter() {
        #expect(toggle(.bulletList, "«one\r\n»two") == "«- one\r\n»two")
        #expect(toggle(.bulletList, "«one\r\ntwo»\r\n") == "«- one\r\n- two»\r\n")
        #expect(toggle(.bulletList, "x\n«one»\ny") == "x\n«- one»\ny")
    }

    @Test func quotesWrapBlankLinesTooAndComeOffOneLevel() {
        #expect(toggle(.quote, "«one\n\ntwo»") == "«> one\n>\n> two»")
        #expect(toggle(.quote, "«> one\n>\n> two»") == "«one\n\ntwo»")
        #expect(toggle(.quote, "«> > deep»") == "«> deep»")
        #expect(toggle(.quote, "«- a\n> b»") == "«> - a\n> b»")
    }
}
