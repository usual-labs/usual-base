import Foundation

/// One change to the editor's text and where the selection goes afterwards.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// The editing helpers, as pure text transforms. Each returns nil when it doesn't apply, so the
/// text view falls back to its normal behaviour.
public enum MarkdownEditing {
    /// Return: continues a list item, task or quote, and ends it when the line is only a marker.
    /// In a document with CRLF line endings, every Return inserts CRLF.
    public static func newline(in text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let content = text.substring(with: contentRange(of: line, in: text))
        let lineEnding = text.substring(with: line).hasSuffix("\r\n") ? "\r\n" : "\n"
        let column = selection.location - line.location

        let continuation: (prefix: String, next: String)?
        if let item = ListPrefix(content) {
            continuation = (item.text, item.continuation)
        } else if let quote = quotePrefix(of: content) {
            continuation = (quote, quote)
        } else {
            continuation = nil
        }

        guard let continuation, column >= continuation.prefix.utf16.count else {
            guard lineEnding == "\r\n" else { return nil }
            return insert(lineEnding, at: selection.location)
        }
        let rest = (content as NSString).substring(from: continuation.prefix.utf16.count)
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item ends the list: remove the marker and stay on the line.
            let length = (content as NSString).length
            return TextEdit(
                range: NSRange(location: line.location, length: length),
                replacement: "",
                selection: NSRange(location: line.location, length: 0)
            )
        }
        return insert(lineEnding + continuation.next, at: selection.location)
    }

    /// Tab on list lines: nests them one level deeper. Nil when no selected line is a list item.
    public static func indent(in text: NSString, selection: NSRange) -> TextEdit? {
        shiftListLines(in: text, selection: selection) { line, item in
            String(repeating: " ", count: item.unit) + line
        }
    }

    /// Shift-Tab on list lines: moves them one level out.
    public static func outdent(in text: NSString, selection: NSRange) -> TextEdit? {
        shiftListLines(in: text, selection: selection) { line, item in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(while: { $0 == " " }).count
            return String(line.dropFirst(min(spaces, item.unit)))
        }
    }

    /// ⌘K or pasting a URL over a selection: makes `[selection](url)`. Without a URL the caret
    /// waits between the parentheses; without a selection it waits between the brackets.
    public static func link(in text: NSString, selection: NSRange, url: String?) -> TextEdit {
        let selected = text.substring(with: selection)
        let replacement = "[\(selected)](\(url ?? ""))"
        let caret: Int
        if selection.length == 0 {
            caret = selection.location + 1
        } else if url == nil {
            caret = selection.location + (replacement as NSString).length - 1
        } else {
            caret = selection.location + (replacement as NSString).length
        }
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: caret, length: 0))
    }

    /// Clicking a task's box: `[ ]` ↔ `[x]`.
    public static func toggleTask(in text: NSString, box: NSRange, selection: NSRange) -> TextEdit? {
        guard box.length == 3, NSMaxRange(box) <= text.length else { return nil }
        let replacement: String
        switch text.substring(with: box) {
        case "[ ]": replacement = "[x]"
        case "[x]", "[X]": replacement = "[ ]"
        default: return nil
        }
        return TextEdit(range: box, replacement: replacement, selection: selection)
    }

    // MARK: - Helpers

    private static func insert(_ string: String, at location: Int) -> TextEdit {
        TextEdit(
            range: NSRange(location: location, length: 0),
            replacement: string,
            selection: NSRange(location: location + (string as NSString).length, length: 0)
        )
    }

    static func contentRange(of line: NSRange, in text: NSString) -> NSRange {
        var end = NSMaxRange(line)
        while end > line.location {
            let c = text.character(at: end - 1)
            guard c == 0x0A || c == 0x0D else { break }
            end -= 1
        }
        return NSRange(location: line.location, length: end - line.location)
    }

    /// `> ` or `> > ` at the start of a line.
    static func quotePrefix(of line: String) -> String? {
        var prefix = ""
        var rest = Substring(line)
        while true {
            let spaces = rest.prefix(while: { $0 == " " })
            guard spaces.count <= 3, rest.dropFirst(spaces.count).first == ">" else { break }
            var marker = String(spaces) + ">"
            rest = rest.dropFirst(marker.count)
            if rest.first == " " {
                marker += " "
                rest = rest.dropFirst()
            }
            prefix += marker
        }
        return prefix.isEmpty ? nil : prefix
    }

    private static func shiftListLines(
        in text: NSString,
        selection: NSRange,
        transform: (String, ListPrefix) -> String
    ) -> TextEdit? {
        let lines = text.lineRange(for: selection)
        var replacement = ""
        var firstDelta: Int?
        var changed = false
        var location = lines.location
        while location < NSMaxRange(lines) {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            let whole = text.substring(with: line)
            var newLine = whole
            if let item = ListPrefix(whole) {
                newLine = transform(whole, item)
                changed = changed || newLine != whole
            }
            if firstDelta == nil { firstDelta = (newLine as NSString).length - line.length }
            replacement += newLine
            location = NSMaxRange(line)
            if line.length == 0 { break }
        }
        guard changed, let firstDelta else { return nil }
        let totalDelta = (replacement as NSString).length - lines.length
        let start = max(lines.location, selection.location + firstDelta)
        let length = selection.length == 0 ? 0 : max(selection.length + totalDelta - firstDelta, 0)
        return TextEdit(range: lines, replacement: replacement, selection: NSRange(location: start, length: length))
    }
}

/// The start of a list line: indentation, marker, spacing and an optional task box.
struct ListPrefix {
    var indent: String
    var marker: String
    var spacing: String
    var checkbox: String?
    var number: Int?

    /// The full prefix as written.
    var text: String { indent + marker + spacing + (checkbox ?? "") }

    /// What Return puts on the next line: the next number, and an unchecked box for tasks.
    var continuation: String {
        var next = marker
        if let number, let delimiter = marker.last { next = "\(number + 1)\(delimiter)" }
        return indent + next + spacing + (checkbox == nil ? "" : "[ ] ")
    }

    /// How far one nesting level moves this item: the width of its marker and spacing.
    var unit: Int { max(marker.count + spacing.count, 2) }

    init?(_ line: String) {
        var rest = Substring(line)
        indent = String(rest.prefix(while: { $0 == " " || $0 == "\t" }))
        rest = rest.dropFirst(indent.count)
        if let first = rest.first, "-*+".contains(first) {
            marker = String(first)
            number = nil
        } else {
            let digits = rest.prefix(while: { $0.isASCII && $0.isNumber })
            guard (1...9).contains(digits.count), let delimiter = rest.dropFirst(digits.count).first,
                delimiter == "." || delimiter == ")"
            else { return nil }
            marker = digits + String(delimiter)
            number = Int(digits)
        }
        rest = rest.dropFirst(marker.count)
        spacing = String(rest.prefix(while: { $0 == " " }))
        guard !spacing.isEmpty else { return nil }
        rest = rest.dropFirst(spacing.count)
        if rest.count >= 3, ["[ ]", "[x]", "[X]"].contains(String(rest.prefix(3))) {
            let after = rest.dropFirst(3)
            if after.isEmpty || after.first == " " || after.first?.isNewline == true {
                checkbox = String(rest.prefix(3)) + String(after.prefix(while: { $0 == " " }))
            }
        }
    }
}
