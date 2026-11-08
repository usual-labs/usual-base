import Foundation

/// Reads and writes Markdown files without ever overwriting a change someone else made.
public enum DocumentStore {
    public enum ReadError: Error, Equatable {
        case notText
    }

    public enum SaveResult: Equatable, Sendable {
        /// The file now holds these bytes (it may already have held them).
        case saved(Data)
        /// The file changed on disk since it was read, so this version went to `copy` instead.
        /// The file keeps `onDisk`.
        case conflict(onDisk: Data, copy: URL)
    }

    public static func read(_ url: URL) throws -> (file: MarkdownFile, data: Data) {
        let data = try Data(contentsOf: url)
        guard let file = MarkdownFile(data: data) else { throw ReadError.notText }
        return (file, data)
    }

    /// Writes `file` if the disk still holds `lastKnown`, the bytes the app last read or wrote.
    /// A file that disappeared is written again, since this version is the only copy left.
    ///
    /// Checking and writing aren't one atomic step, so an agent writing in the same instant can
    /// still lose that write. Git history is the backstop once sync exists.
    public static func save(
        _ file: MarkdownFile,
        to url: URL,
        lastKnown: Data?,
        now: Date = .now
    ) throws -> SaveResult {
        let data = file.data
        let onDisk = try? Data(contentsOf: url)
        if let onDisk, onDisk == data { return .saved(data) }
        if let onDisk, let lastKnown, onDisk != lastKnown {
            let copy = conflictCopyURL(for: url, date: now)
            try data.write(to: copy, options: .withoutOverwriting)
            return .conflict(onDisk: onDisk, copy: copy)
        }
        try data.write(to: url, options: .atomic)
        return .saved(data)
    }

    /// See ``ConflictCopy``.
    public static func conflictCopyURL(for url: URL, date: Date) -> URL {
        let path = ConflictCopy.path(for: url.path(percentEncoded: false), date: date) {
            FileManager.default.fileExists(atPath: $0)
        }
        return URL(filePath: path)
    }
}
