import Foundation

/// A Markdown file split into the parts the app treats differently.
///
/// Agents write these files too, so the split is lossless: `data` gives back the exact bytes
/// that were read. The editor only ever holds `body`; front matter and a byte-order mark are
/// carried around untouched unless someone edits them on purpose.
public struct MarkdownFile: Equatable, Sendable {
    /// The raw front-matter block: both fence lines, the YAML between them, and the line ending
    /// after the closing fence. Empty when the file has none.
    public var frontMatter: String
    public var body: String
    public var byteOrderMark: Bool

    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    public init(text: String, byteOrderMark: Bool = false) {
        (frontMatter, body) = Self.split(text)
        self.byteOrderMark = byteOrderMark
    }

    /// Returns nil when the bytes aren't UTF-8 text.
    public init?(data: Data) {
        let hasBOM = data.starts(with: Self.bom)
        guard let text = String(data: hasBOM ? data.dropFirst(Self.bom.count) : data, encoding: .utf8) else {
            return nil
        }
        self.init(text: text, byteOrderMark: hasBOM)
    }

    public var text: String { frontMatter + body }

    public var data: Data {
        (byteOrderMark ? Data(Self.bom) : Data()) + Data(text.utf8)
    }

    /// The YAML between the fences, or nil when there is no front matter.
    public var frontMatterYAML: String? {
        guard let fences = fences else { return nil }
        let ns = frontMatter as NSString
        return ns.substring(
            with: NSRange(location: fences.opening.length, length: fences.closing.location - fences.opening.length))
    }

    /// Replaces the YAML between the fences, keeping both fence lines exactly as they were.
    public func replacingFrontMatterYAML(_ yaml: String) -> MarkdownFile {
        guard let fences = fences else { return self }
        let ns = frontMatter as NSString
        let lineEnding = ns.substring(with: fences.opening).hasSuffix("\r\n") ? "\r\n" : "\n"
        var inner = yaml
        if !inner.isEmpty && !endsWithLineBreak(inner) { inner += lineEnding }
        var copy = self
        copy.frontMatter = ns.substring(with: fences.opening) + inner + ns.substring(from: fences.closing.location)
        return copy
    }

    /// The opening fence line and the closing fence line (each with its line ending) inside `frontMatter`.
    private var fences: (opening: NSRange, closing: NSRange)? {
        guard !frontMatter.isEmpty else { return nil }
        let ns = frontMatter as NSString
        let opening = ns.lineRange(for: NSRange(location: 0, length: 0))
        // The closing fence is always the last line of the block.
        let closing = ns.lineRange(for: NSRange(location: ns.length - 1, length: 0))
        return (opening, closing)
    }

    /// Front matter starts on the first line with `---` and ends at the next line that is `---` or `...`.
    /// Without a closing fence the whole text is body.
    private static func split(_ text: String) -> (frontMatter: String, body: String) {
        let ns = text as NSString
        let first = ns.lineRange(for: NSRange(location: 0, length: 0))
        guard first.length > 0, trimmed(ns.substring(with: first)) == "---",
            endsWithLineBreak(ns.substring(with: first))
        else { return ("", text) }
        var location = NSMaxRange(first)
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let content = trimmed(ns.substring(with: line))
            if content == "---" || content == "..." {
                return (ns.substring(to: NSMaxRange(line)), ns.substring(from: NSMaxRange(line)))
            }
            location = NSMaxRange(line)
        }
        return ("", text)
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Checks scalars, not Characters: in Swift `"\r\n"` is one Character, so `hasSuffix("\n")` misses it.
func endsWithLineBreak(_ text: String) -> Bool {
    guard let last = text.unicodeScalars.last else { return false }
    return last == "\n" || last == "\r"
}
