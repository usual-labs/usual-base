import Foundation

/// `http://` and `https://` addresses written as plain text. swift-markdown doesn't turn these
/// into links, so the highlighter and the renderer find them here.
enum BareURLs {
    /// The addresses inside `range` of `text`, without sentence punctuation after them.
    static func ranges(in text: NSString, range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var searchRange = range
        while searchRange.length > 0 {
            let found = text.range(of: "http", options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            let rest = text.substring(
                with: NSRange(location: found.location, length: min(8, NSMaxRange(range) - found.location)))
            let startsURL = rest.hasPrefix("https://") || rest.hasPrefix("http://")
            let wordStart =
                found.location == range.location || !isWordCharacter(character(in: text, at: found.location - 1))
            var end = found.location
            if startsURL && wordStart {
                while end < NSMaxRange(range), let c = character(in: text, at: end), !isTerminator(c) { end += 1 }
                end = trimTrailingPunctuation(in: text, start: found.location, end: end)
                if end > found.location + 8 {
                    result.append(NSRange(location: found.location, length: end - found.location))
                }
            }
            let next = max(end, found.location + 4)
            searchRange = NSRange(location: next, length: max(NSMaxRange(range) - next, 0))
        }
        return result
    }

    private static func character(in text: NSString, at offset: Int) -> unichar? {
        offset >= 0 && offset < text.length ? text.character(at: offset) : nil
    }

    private static func isWordCharacter(_ c: unichar?) -> Bool {
        guard let c, let scalar = Unicode.Scalar(c) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func isTerminator(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x3C || c == 0x3E  // space, tab, newlines, < >
    }

    /// Drops sentence punctuation after an address, and a closing parenthesis that has no opening one.
    private static func trimTrailingPunctuation(in text: NSString, start: Int, end: Int) -> Int {
        var end = end
        // . , ; : ! ? ' " ] }
        let punctuation: Set<unichar> = [0x2E, 0x2C, 0x3B, 0x3A, 0x21, 0x3F, 0x27, 0x22, 0x5D, 0x7D]
        while end > start, let c = character(in: text, at: end - 1) {
            if punctuation.contains(c) {
                end -= 1
            } else if c == 0x29 && !text.substring(with: NSRange(location: start, length: end - start)).contains("(") {
                end -= 1
            } else {
                break
            }
        }
        return end
    }
}
