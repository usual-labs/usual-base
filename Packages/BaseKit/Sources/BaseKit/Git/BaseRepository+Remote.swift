import Clibgit2
import Foundation

/// Fetching from and pushing to `origin`.
extension BaseRepository {
    /// Fetches `origin`'s branches. Returns the remote's default branch, or nil for an empty
    /// remote.
    func fetchOrigin(_ credentials: GitCredentials?) throws -> String? {
        let remote = try lookupOrigin()
        var options = git_fetch_options()
        try check(git_fetch_options_init(&options, UInt32(GIT_FETCH_OPTIONS_VERSION)))
        options.download_tags = GIT_REMOTE_DOWNLOAD_TAGS_NONE
        options.prune = GIT_FETCH_PRUNE
        let session = RemoteSession(credentials: credentials)
        session.install(in: &options.callbacks)
        try withExtendedLifetime(session) {
            try session.verify(git_remote_fetch(remote.pointer, nil, &options, nil))
        }
        // libgit2 keeps the advertised refs after disconnecting, so this needs no second request.
        var buffer = git_buf()
        defer { git_buf_dispose(&buffer) }
        guard git_remote_default_branch(&buffer, remote.pointer) == 0, let pointer = buffer.ptr else { return nil }
        let ref = String(cString: pointer)
        return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : nil
    }

    /// Pushes the current branch to the same branch on `origin`. Returns nil on success, or the
    /// reason the remote refused it, usually because it has commits this Mac hasn't fetched.
    func push(_ credentials: GitCredentials?) throws -> String? {
        let branch = try branchName()
        let remote = try lookupOrigin()
        var options = git_push_options()
        try check(git_push_options_init(&options, UInt32(GIT_PUSH_OPTIONS_VERSION)))
        let session = RemoteSession(credentials: credentials)
        session.install(in: &options.callbacks)
        let code = withExtendedLifetime(session) {
            withStrArray(["refs/heads/\(branch):refs/heads/\(branch)"]) {
                git_remote_push(remote.pointer, $0, &options)
            }
        }
        if code == GIT_ENONFASTFORWARD.rawValue { return "the remote has newer commits" }
        try session.verify(code)
        if let refusal = session.refusal { return refusal }
        try rememberUpstream(branch)
        return nil
    }
}

/// State shared with libgit2's network callbacks for one fetch or push.
private final class RemoteSession {
    let credentials: GitCredentials?
    var credentialRequests = 0
    var refusal: String?

    init(credentials: GitCredentials?) {
        self.credentials = credentials
    }

    func install(in callbacks: inout git_remote_callbacks) {
        callbacks.payload = Unmanaged.passUnretained(self).toOpaque()
        callbacks.credentials = { out, _, _, allowedTypes, payload in
            guard let payload else { return GIT_EAUTH.rawValue }
            let session = Unmanaged<RemoteSession>.fromOpaque(payload).takeUnretainedValue()
            session.credentialRequests += 1
            // A second request means the remote refused the first answer; asking again would
            // loop.
            guard session.credentialRequests == 1, let credentials = session.credentials,
                allowedTypes & GIT_CREDENTIAL_USERPASS_PLAINTEXT.rawValue != 0
            else { return GIT_EAUTH.rawValue }
            return git_credential_userpass_plaintext_new(out, credentials.username, credentials.token)
        }
        callbacks.push_update_reference = { _, status, payload in
            if let status, let payload {
                Unmanaged<RemoteSession>.fromOpaque(payload).takeUnretainedValue().refusal = String(cString: status)
            }
            return 0
        }
    }

    /// Like `check`, but reports a refused or missing credential as such.
    func verify(_ code: Int32) throws {
        guard code < 0 else { return }
        if code == GIT_EAUTH.rawValue || credentialRequests > 1 { throw SyncError.authenticationFailed }
        throw GitError(code: code)
    }
}
