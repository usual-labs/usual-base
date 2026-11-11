import Foundation

/// Paths for renaming and copying a file in a Base. Paths are relative to the Base, with `/`.
public enum FileNames {
    /// The path for the file at `path` renamed to `name`, in the same folder. A name without a
    /// Markdown extension keeps the file's own. Nil for a name that isn't one visible file name.
    public static func renaming(_ path: String, to name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return nil }
        let old = path as NSString
        let hasMarkdownExtension = BaseIndex.markdownExtensions.contains((name as NSString).pathExtension.lowercased())
        let file = hasMarkdownExtension || old.pathExtension.isEmpty ? name : name + "." + old.pathExtension
        return join(old.deletingLastPathComponent, file)
    }

    /// A path for a copy of `path` that doesn't exist yet: "Plan copy.md", then "Plan copy 2.md".
    public static func copy(of path: String, exists: (String) -> Bool) -> String {
        let old = path as NSString
        let folder = old.deletingLastPathComponent
        let stem = (old.lastPathComponent as NSString).deletingPathExtension
        let suffix = old.pathExtension.isEmpty ? "" : "." + old.pathExtension
        var number = 1
        while true {
            let candidate = join(folder, stem + (number == 1 ? " copy" : " copy \(number)") + suffix)
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    private static func join(_ folder: String, _ file: String) -> String {
        folder.isEmpty ? file : folder + "/" + file
    }
}
