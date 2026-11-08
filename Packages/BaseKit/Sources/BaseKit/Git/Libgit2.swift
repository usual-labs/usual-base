import CGitShim
import Clibgit2
import Foundation

/// Process-wide libgit2 setup, done once before the first repository opens.
enum Libgit2 {
    /// A stalled connection gives up instead of blocking every later sync.
    private static let startResult = usualbase_git_start("UsualBase", 15_000, 60_000)

    static func start() throws {
        try check(startResult)
    }
}

/// A libgit2 failure, with libgit2's own message.
struct GitError: Error, CustomStringConvertible {
    let code: Int32
    let category: Int32
    let message: String

    init(code: Int32) {
        self.code = code
        let last = git_error_last()
        category = last?.pointee.klass ?? 0
        message = last?.pointee.message.map { String(cString: $0) } ?? "libgit2 error \(code)"
    }

    var description: String { message }

    var isNetwork: Bool {
        [GIT_ERROR_NET, GIT_ERROR_SSL, GIT_ERROR_HTTP].contains { Int32($0.rawValue) == category }
            || code == GIT_ECERTIFICATE.rawValue
    }
}

func check(_ code: Int32) throws {
    if code < 0 { throw GitError(code: code) }
}

/// A git object ID.
struct ObjectID: Hashable, CustomStringConvertible {
    var raw: git_oid

    init(_ raw: git_oid) { self.raw = raw }

    private var bytes: [UInt8] { withUnsafeBytes(of: raw) { Array($0) } }

    static func == (lhs: ObjectID, rhs: ObjectID) -> Bool { lhs.bytes == rhs.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(bytes) }

    var description: String {
        var raw = raw
        return String(cString: git_oid_tostr_s(&raw))
    }
}

/// Owns a libgit2 object and frees it with the matching `git_*_free`.
final class Owned<Pointer> {
    let pointer: Pointer
    private let free: (Pointer?) -> Void

    init(_ pointer: Pointer, free: @escaping (Pointer?) -> Void) {
        self.pointer = pointer
        self.free = free
    }

    deinit { free(pointer) }
}

/// Runs a libgit2 constructor and takes ownership of what it made.
func make<Pointer>(_ free: @escaping (Pointer?) -> Void, _ create: (inout Pointer?) -> Int32) throws -> Owned<Pointer> {
    var pointer: Pointer?
    try check(create(&pointer))
    guard let pointer else { throw GitError(code: GIT_ERROR.rawValue) }
    return Owned(pointer, free: free)
}

/// Lends `strings` to libgit2 as a `git_strarray`.
func withStrArray<Result>(_ strings: [String], _ body: (UnsafeMutablePointer<git_strarray>) throws -> Result) rethrows
    -> Result
{
    var copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    return try copies.withUnsafeMutableBufferPointer { buffer in
        var array = git_strarray(strings: buffer.baseAddress, count: buffer.count)
        return try body(&array)
    }
}

extension GitIdentity {
    func signature(at date: Date) throws -> Owned<UnsafeMutablePointer<git_signature>> {
        let minutesFromGMT = Int32(TimeZone.current.secondsFromGMT(for: date) / 60)
        return try make(git_signature_free) {
            git_signature_new(&$0, name, email, git_time_t(date.timeIntervalSince1970), minutesFromGMT)
        }
    }
}
