import Foundation

/// Headings, lists, tasks and quotes: formats that change the start of each selected line.
extension MarkdownEditing {
    static func linesHave(_ format: MarkdownFormat, _ lines: [LineParts]) -> Bool {
        let written = lines.filter { !$0.isBlank }
        return (written.isEmpty ? lines : written).allSatisfy { line in
            switch format {
            case .heading(let level): level <= 0 ? !line.isHeading : line.kind == .heading(min(level, 6))
            case .bulletList: line.kind == .bullet && line.box == nil
            case .numberedList: line.kind == .ordered && line.box == nil
            case .taskList: line.box != nil
            case .quote: !line.quote.isEmpty
            default: false
            }
        }
    }

    static func toggleLines(_ format: MarkdownFormat, in text: NSString, selection: NSRange) -> TextEdit? {
        let ranges = selectedLines(selection, in: text)
        let lines = ranges.map { LineParts(text.substring(with: $0)) }
        let isApplied = linesHave(format, lines)
        let onlyBlank = lines.allSatisfy(\.isBlank)
        var numbers: [String: Int] = [:]
        let newLines = lines.map { line -> String in
            if line.isBlank, !onlyBlank, format != .quote { return line.text }
            let (quote, indent, content) = (line.quote, line.indent, line.content)
            switch format {
            case .heading(let level):
                let target = isApplied && level > 0 ? 0 : min(max(level, 0), 6)
                if target > 0 { return quote + String(repeating: "#", count: target) + " " + content }
                return line.isHeading ? quote + indent + content : line.text
            case .bulletList:
                if isApplied { return quote + indent + content }
                return line.kind == .bullet && line.box == nil ? line.text : quote + indent + "- " + content
            case .numberedList:
                if isApplied { return quote + indent + content }
                // Count each nesting level on its own, starting again under each new parent.
                numbers = numbers.filter { $0.key.count <= indent.count }
                let number = (numbers[indent] ?? 0) + 1
                numbers[indent] = number
                return quote + indent + "\(number). " + content
            case .taskList:
                if isApplied { return quote + indent + content }
                if line.box != nil { return line.text }
                let isListItem = line.kind == .bullet || line.kind == .ordered
                return quote + indent + (isListItem ? line.marker : "- ") + "[ ] " + content
            case .quote:
                if isApplied { return line.removingOneQuoteLevel }
                if !quote.isEmpty { return line.text }
                return line.text.isEmpty ? ">" : "> " + line.text
            default:
                return line.text
            }
        }
        guard newLines != lines.map(\.text) else { return nil }

        // The new text, with each line's original ending.
        let start = ranges[0].location
        let editRange = NSRange(location: start, length: NSMaxRange(ranges[ranges.count - 1]) - start)
        var replacement = ""
        var newStarts: [Int] = []
        for index in lines.indices {
            newStarts.append(start + replacement.utf16.count)
            replacement += newLines[index]
            if index + 1 < ranges.count {
                let ending = NSMaxRange(ranges[index])
                replacement += text.substring(
                    with: NSRange(location: ending, length: ranges[index + 1].location - ending))
            }
        }
        let delta = replacement.utf16.count - editRange.length

        /// Where a location in the old text ends up: text keeps its place after the new markers.
        func map(_ location: Int, keepingLineStart: Bool) -> Int {
            guard location <= NSMaxRange(editRange) else { return location + delta }
            let index = ranges.lastIndex { $0.location <= location } ?? 0
            let offset = location - ranges[index].location
            if offset == 0, keepingLineStart { return newStarts[index] }
            let newPrefix = LineParts(newLines[index]).prefixLength
            let mapped = newStarts[index] + newPrefix + max(0, offset - lines[index].prefixLength)
            return min(mapped, newStarts[index] + newLines[index].utf16.count)
        }
        let newStart = map(selection.location, keepingLineStart: selection.length > 0)
        let newEnd = selection.length == 0 ? newStart : map(NSMaxRange(selection), keepingLineStart: true)
        return TextEdit(
            range: editRange,
            replacement: replacement,
            selection: NSRange(location: newStart, length: newEnd - newStart)
        )
    }

    /// The lines the selection touches, without their line endings. A selection that ends at the
    /// start of a line, as a triple-click does, leaves that line out.
    static func selectedLines(_ selection: NSRange, in text: NSString) -> [NSRange] {
        var range = selection
        if range.length > 0, [0x0A, 0x0D].contains(text.character(at: NSMaxRange(range) - 1)) { range.length -= 1 }
        let lines = text.lineRange(for: range)
        var result: [NSRange] = []
        var location = lines.location
        repeat {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            result.append(contentRange(of: line, in: text))
            location = NSMaxRange(line)
        } while location < NSMaxRange(lines)
        return result
    }
}

/// A line split into its block markers and its text: quote markers, then indentation and either
/// a list marker with an optional task box, or a heading's `#`s.
struct LineParts {
    enum Kind: Equatable {
        case plain, heading(Int), bullet, ordered
    }

    var quote = ""
    var indent = ""
    var marker = ""
    var box: String?
    var kind = Kind.plain
    var content = ""

    init(_ line: String) {
        quote = MarkdownEditing.quotePrefix(of: line) ?? ""
        var rest = Substring(line).dropFirst(quote.count)
        if let item = ListPrefix(String(rest)) {
            indent = item.indent
            marker = item.marker + item.spacing
            box = item.checkbox
            kind = item.number == nil ? .bullet : .ordered
            rest = rest.dropFirst(item.text.count)
        } else {
            indent = String(rest.prefix(while: { $0 == " " || $0 == "\t" }))
            rest = rest.dropFirst(indent.count)
            let hashes = rest.prefix(while: { $0 == "#" })
            let after = rest.dropFirst(hashes.count)
            if (1...6).contains(hashes.count), after.first == nil || after.first == " " || after.first == "\t" {
                marker = String(hashes) + after.prefix(while: { $0 == " " || $0 == "\t" })
                kind = .heading(hashes.count)
                rest = rest.dropFirst(marker.count)
            }
        }
        content = String(rest)
    }

    /// The line as written.
    var text: String { quote + indent + marker + (box ?? "") + content }

    /// The length of everything before the text, in UTF-16 units.
    var prefixLength: Int { (quote + indent + marker + (box ?? "")).utf16.count }

    /// No text and no list or heading marker, though it may be inside a quote.
    var isBlank: Bool { kind == .plain && content.allSatisfy(\.isWhitespace) }

    var isHeading: Bool {
        if case .heading = kind { return true }
        return false
    }

    /// The line one quote level further out: `> > a` becomes `> a`.
    var removingOneQuoteLevel: String {
        guard let marker = quote.firstIndex(of: ">") else { return text }
        var outer = quote
        let next = quote.index(after: marker)
        outer.removeSubrange(marker..<(next < quote.endIndex && quote[next] == " " ? quote.index(after: next) : next))
        return outer + indent + self.marker + (box ?? "") + content
    }
}
