import Foundation

/// Where a version that lost a clash goes: `Notes (conflict 2026-11-06 14.05).md` next to the
/// original, numbered if that name is taken. Saves and syncs use the same names.
public enum ConflictCopy {
    /// `path` uses `/` separators, relative or absolute. `isTaken` says whether a path exists.
    public static func path(for path: String, date: Date, isTaken: (String) -> Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let stamp = formatter.string(from: date)
        let folder = (path as NSString).deletingLastPathComponent
        let fileName = (path as NSString).lastPathComponent
        let ext = (fileName as NSString).pathExtension
        let name = (fileName as NSString).deletingPathExtension
        var attempt = 1
        while true {
            let suffix = attempt == 1 ? "" : " \(attempt)"
            let candidateName = "\(name) (conflict \(stamp)\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = folder.isEmpty ? candidateName : folder + "/" + candidateName
            if !isTaken(candidate) { return candidate }
            attempt += 1
        }
    }
}
