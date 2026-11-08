import Foundation

/// A command from the Format menu or the bar over selected text.
public enum MarkdownFormat: Hashable, Sendable {
    case bold, italic, strikethrough, code, link
    /// A heading of level 1 to 6. Level 0 is body text.
    case heading(Int)
    case bulletList, numberedList, taskList, quote
}

extension MarkdownEditing {
    /// Whether the selection already has `format`, so `toggle` would take it off.
    public static func isApplied(_ format: MarkdownFormat, in text: NSString, selection: NSRange) -> Bool {
        if format == .link { return linkAround(selection, in: text) != nil }
        if let style = InlineStyle(format) {
            let segments = inlineSegments(of: selection, in: text)
            return !segments.isEmpty && segments.allSatisfy { style.pair(in: $0) != nil }
        }
        return linesHave(format, selectedLines(selection, in: text).map { LineParts(text.substring(with: $0)) })
    }

    /// Adds `format` to the selection, or takes it off when the selection already has it.
    /// Inline formats wrap each selected line's text, leaving out its list or heading marker and
    /// the spaces around it. `url` is the destination for a new link. Nil when nothing changes.
    public static func toggle(
        _ format: MarkdownFormat, in text: NSString, selection: NSRange, url: String? = nil
    ) -> TextEdit? {
        if format == .link { return toggleLink(in: text, selection: selection, url: url) }
        if let style = InlineStyle(format) { return toggle(style, in: text, selection: selection) }
        return toggleLines(format, in: text, selection: selection)
    }

    // MARK: - Inline styles

    private static func toggle(_ style: InlineStyle, in text: NSString, selection: NSRange) -> TextEdit? {
        let segments = inlineSegments(of: selection, in: text)
        guard !segments.isEmpty else { return nil }
        let pairs = segments.map(style.pair)
        let isApplied = pairs.allSatisfy { $0 != nil }
        let changes = zip(segments, pairs).map { segment, pair in
            if isApplied, let pair {
                let width = style.width(inRunOf: min(pair.before.range.length, pair.after.range.length))
                return SegmentChange(
                    core: segment.core,
                    before: NSRange(location: NSMaxRange(pair.before.range) - width, length: width),
                    after: NSRange(location: pair.after.range.location, length: width))
            }
            guard !isApplied, pair == nil else { return SegmentChange(unchanged: segment.core) }
            // New markers go outside inline code, where they'd otherwise show as text.
            var start = segment.core.location
            var end = NSMaxRange(segment.core)
            if style != .code, let before = segment.before.first, let after = segment.after.first,
                before.character == backtick, after.character == backtick
            {
                start = before.range.location
                end = NSMaxRange(after.range)
            }
            return SegmentChange(
                core: segment.core,
                before: NSRange(location: start, length: 0), beforeText: style.marker,
                after: NSRange(location: end, length: 0), afterText: style.marker)
        }
        return combine(changes, in: text)
    }

    /// Each selected line's part of the selection. A caret is one empty segment.
    private static func inlineSegments(of selection: NSRange, in text: NSString) -> [InlineSegment] {
        if selection.length == 0 {
            let line = contentRange(of: text.lineRange(for: selection), in: text)
            return InlineSegment(selection, line: line, in: text).map { [$0] } ?? []
        }
        return selectedLines(selection, in: text).compactMap { line in
            let textStart = line.location + LineParts(text.substring(with: line)).prefixLength
            let start = max(selection.location, textStart)
            let end = min(NSMaxRange(selection), NSMaxRange(line))
            guard start < end else { return nil }
            return InlineSegment(NSRange(location: start, length: end - start), line: line, in: text)
        }
    }

    /// One edit for every segment's change, selecting from the first core to the last.
    private static func combine(_ changes: [SegmentChange], in text: NSString) -> TextEdit {
        let start = changes[0].before.location
        let end = NSMaxRange(changes[changes.count - 1].after)
        let output = NSMutableString()
        var cursor = start
        var selectionStart = start
        var selectionEnd = start
        func copy(upTo location: Int) {
            output.append(text.substring(with: NSRange(location: cursor, length: location - cursor)))
            cursor = location
        }
        for (index, change) in changes.enumerated() {
            copy(upTo: change.before.location)
            output.append(change.beforeText)
            cursor = NSMaxRange(change.before)
            copy(upTo: change.core.location)
            if index == 0 { selectionStart = start + output.length }
            copy(upTo: NSMaxRange(change.core))
            selectionEnd = start + output.length
            copy(upTo: change.after.location)
            output.append(change.afterText)
            cursor = NSMaxRange(change.after)
        }
        return TextEdit(
            range: NSRange(location: start, length: end - start),
            replacement: output as String,
            selection: NSRange(location: selectionStart, length: selectionEnd - selectionStart)
        )
    }

    // MARK: - Links

    private static func toggleLink(in text: NSString, selection: NSRange, url: String?) -> TextEdit {
        if let found = linkAround(selection, in: text) {
            let label = text.substring(with: found.label)
            return TextEdit(
                range: found.link,
                replacement: label,
                selection: NSRange(location: found.link.location, length: (label as NSString).length)
            )
        }
        var range = selection
        let segments = inlineSegments(of: selection, in: text)
        if selection.length > 0, let first = segments.first?.trimmed, let last = segments.last?.trimmed {
            range = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        }
        return link(in: text, selection: range, url: url)
    }

    /// The `[label](destination)` on the selection's line that holds the selection. Pictures
    /// don't count.
    private static func linkAround(_ selection: NSRange, in text: NSString) -> (link: NSRange, label: NSRange)? {
        let line = contentRange(of: text.lineRange(for: NSRange(location: selection.location, length: 0)), in: text)
        let end = NSMaxRange(line)
        guard NSMaxRange(selection) <= end else { return nil }
        func next(after start: Int, closing: unichar, opening: unichar) -> Int? {
            var index = start
            while index < end {
                let character = text.character(at: index)
                if character == closing { return index }
                if character == opening { return nil }
                index += 1
            }
            return nil
        }
        for open in line.location..<end where text.character(at: open) == 0x5B {  // [
            if open > line.location, text.character(at: open - 1) == 0x21 { continue }  // ![picture]
            guard let close = next(after: open + 1, closing: 0x5D, opening: 0x5B),  // ]
                close + 1 < end, text.character(at: close + 1) == 0x28,  // (
                let paren = next(after: close + 2, closing: 0x29, opening: 0x28)  // )
            else { continue }
            let link = NSRange(location: open, length: paren + 1 - open)
            if link.location <= selection.location, NSMaxRange(selection) <= NSMaxRange(link) {
                return (link, NSRange(location: open + 1, length: close - open - 1))
            }
        }
        return nil
    }
}

private let star: unichar = 0x2A
private let underscore: unichar = 0x5F
private let tilde: unichar = 0x7E
private let backtick: unichar = 0x60

/// Bold, italic, strikethrough and code: text between runs of marker characters.
private enum InlineStyle {
    case bold, italic, strikethrough, code

    init?(_ format: MarkdownFormat) {
        switch format {
        case .bold: self = .bold
        case .italic: self = .italic
        case .strikethrough: self = .strikethrough
        case .code: self = .code
        default: return nil
        }
    }

    var marker: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
        case .code: "`"
        }
    }

    private func matches(_ character: unichar) -> Bool {
        switch self {
        case .bold, .italic: character == star || character == underscore
        case .strikethrough: character == tilde
        case .code: character == backtick
        }
    }

    /// Whether a run this long carries the style: `***` is both bold and italic.
    private func isCarried(byRunOf length: Int) -> Bool {
        switch self {
        case .bold: length >= 2
        case .italic: length % 2 == 1
        case .strikethrough, .code: length >= 1
        }
    }

    /// How many characters taking the style off removes from each run.
    func width(inRunOf length: Int) -> Int {
        switch self {
        case .bold: 2
        case .italic: 1
        case .strikethrough: min(length, 2)
        case .code: length
        }
    }

    /// The innermost runs around the segment that give it this style.
    func pair(in segment: InlineSegment) -> (before: MarkerRun, after: MarkerRun)? {
        let carries = { (run: MarkerRun) in matches(run.character) && isCarried(byRunOf: run.range.length) }
        guard let before = segment.before.first(where: carries), let after = segment.after.first(where: carries),
            before.character == after.character, self != .code || before.range.length == after.range.length
        else { return nil }
        return (before, after)
    }
}

/// A run of one marker character, such as the `**` of bold.
private struct MarkerRun {
    var character: unichar
    var range: NSRange
}

/// One line's part of the selection: `trimmed` leaves out the spaces around it, `core` also
/// leaves out marker characters at its ends. `before` and `after` are the runs of marker
/// characters around the core, innermost first.
private struct InlineSegment {
    var trimmed: NSRange
    var core: NSRange
    var before: [MarkerRun]
    var after: [MarkerRun]

    /// Nil for a range of only spaces or only markers.
    init?(_ range: NSRange, line: NSRange, in text: NSString) {
        func isSpace(_ character: unichar) -> Bool { [0x20, 0x09, 0x0A, 0x0D].contains(character) }
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isSpace(text.character(at: start)) { start += 1 }
        while end > start, isSpace(text.character(at: end - 1)) { end -= 1 }
        var coreStart = start
        var coreEnd = end
        while coreStart < coreEnd, Self.isMarker(text.character(at: coreStart)) { coreStart += 1 }
        while coreEnd > coreStart, Self.isMarker(text.character(at: coreEnd - 1)) { coreEnd -= 1 }
        guard range.length == 0 || coreStart < coreEnd else { return nil }
        trimmed = NSRange(location: start, length: end - start)
        core = NSRange(location: coreStart, length: coreEnd - coreStart)
        before = Self.runs(from: coreStart, to: line.location, in: text)
        after = Self.runs(from: coreEnd, to: NSMaxRange(line), in: text)
    }

    private static func isMarker(_ character: unichar) -> Bool {
        character == star || character == underscore || character == tilde || character == backtick
    }

    /// The runs of marker characters from `location` towards `limit`, nearest first.
    private static func runs(from location: Int, to limit: Int, in text: NSString) -> [MarkerRun] {
        let step = limit < location ? -1 : 1
        func character(at index: Int) -> unichar { text.character(at: step < 0 ? index - 1 : index) }
        var runs: [MarkerRun] = []
        var index = location
        while index != limit, isMarker(character(at: index)) {
            let marker = character(at: index)
            let first = index
            while index != limit, character(at: index) == marker { index += step }
            let range = NSRange(location: min(first, index), length: abs(index - first))
            runs.append(MarkerRun(character: marker, range: range))
        }
        return runs
    }
}

/// What a format does around one segment: the ranges to replace before and after its core.
private struct SegmentChange {
    var core: NSRange
    var before: NSRange
    var beforeText = ""
    var after: NSRange
    var afterText = ""

    init(core: NSRange, before: NSRange, beforeText: String = "", after: NSRange, afterText: String = "") {
        self.core = core
        self.before = before
        self.beforeText = beforeText
        self.after = after
        self.afterText = afterText
    }

    init(unchanged core: NSRange) {
        self.init(
            core: core, before: NSRange(location: core.location, length: 0),
            after: NSRange(location: NSMaxRange(core), length: 0))
    }
}
