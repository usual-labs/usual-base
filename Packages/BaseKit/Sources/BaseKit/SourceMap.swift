import Foundation
import Markdown

/// Converts swift-markdown source locations into UTF-16 offsets for `NSRange`.
///
/// swift-markdown reports 1-based lines and 1-based columns counted in UTF-8 bytes, with
/// exclusive upper bounds. Line breaks follow cmark: `\n`, `\r\n` and a lone `\r`.
struct SourceMap {
    let text: String
    private var lineStartsUTF8: [Int] = [0]
    private var lineStartsUTF16: [Int] = [0]
    private var lineIsASCII: [Bool] = []
    let utf16Length: Int

    init(_ text: String) {
        self.text = text
        var utf16 = 0
        var ascii = true
        let bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0..<0x80: utf16 += 1
            case 0xF0...: utf16 += 2  // a four-byte sequence is a surrogate pair in UTF-16
            case 0xC0...: utf16 += 1
            default: break  // continuation byte
            }
            if byte >= 0x80 { ascii = false }
            let isBreak = byte == 0x0A || (byte == 0x0D && (index + 1 == bytes.count || bytes[index + 1] != 0x0A))
            if isBreak {
                lineIsASCII.append(ascii)
                ascii = true
                lineStartsUTF8.append(index + 1)
                lineStartsUTF16.append(utf16)
            }
            index += 1
        }
        lineIsASCII.append(ascii)
        utf16Length = utf16
    }

    var lineCount: Int { lineStartsUTF16.count }

    /// The UTF-16 offset of a 1-based line and UTF-8 column.
    func offset(_ location: SourceLocation) -> Int {
        let line = min(max(location.line - 1, 0), lineCount - 1)
        let bytes = max(location.column - 1, 0)
        if lineIsASCII[line] { return min(lineStartsUTF16[line] + bytes, utf16Length) }
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: lineStartsUTF8[line])
        let end = utf8.index(start, offsetBy: bytes, limitedBy: utf8.endIndex) ?? utf8.endIndex
        return lineStartsUTF16[line] + text.utf16.distance(from: start, to: end)
    }

    func range(_ range: SourceRange?) -> NSRange? {
        guard let range else { return nil }
        let lower = offset(range.lowerBound)
        return NSRange(location: lower, length: max(offset(range.upperBound) - lower, 0))
    }

    /// The whole lines a source range touches, including the last line's line break.
    /// A range that ends at column 1 of a line doesn't touch that line.
    func lines(_ range: SourceRange?) -> NSRange? {
        guard let range else { return nil }
        let first = range.lowerBound.line - 1
        var last = range.upperBound.line - 1
        if last > first && range.upperBound.column == 1 { last -= 1 }
        return lines(first...max(first, last))
    }

    /// Whole lines by 0-based index, including the last line's line break.
    func lines(_ indices: ClosedRange<Int>) -> NSRange {
        let first = min(max(indices.lowerBound, 0), lineCount - 1)
        let last = min(max(indices.upperBound, first), lineCount - 1)
        let start = lineStartsUTF16[first]
        let end = last + 1 < lineCount ? lineStartsUTF16[last + 1] : utf16Length
        return NSRange(location: start, length: end - start)
    }

    /// The 0-based line containing a UTF-16 offset.
    func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lineCount - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartsUTF16[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}
