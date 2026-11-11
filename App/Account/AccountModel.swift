import AppKit
import BaseKit
import Observation

/// The hosted Usual Base account on this Mac: signing in, the account's Bases, and where their clones live.
/// The Mac signs in like an agent does: it shows a code, the person approves it in the browser, and the Mac
/// gets its own token, kept in the keychain.
@MainActor @Observable
final class AccountModel {
    enum State: Equatable {
        case signedOut
        case signingIn(code: String, url: URL)
        case signedIn
    }

    private(set) var state: State = .signedOut
    private(set) var email: String?
    private(set) var bases: [HostedBase] = []
    /// A one-line message about signing in or listing Bases, shown as an alert.
    var problem: String?
    /// Runs after signing in, so an open hosted Base picks up the new token.
    @ObservationIgnored var didSignIn: () -> Void = {}

    let api: AccountAPI
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var accessedFolder: URL?
    private static let folderKey = "hostedBasesFolderBookmark"

    init() {
        var server = URL(string: "https://base.usual.dev")!
        #if DEBUG
            // A local server for development: `npm run dev` in cloud/.
            if let override = ProcessInfo.processInfo.environment["USUALBASE_SERVER"].flatMap(URL.init(string:)) {
                server = override
            }
        #endif
        api = AccountAPI(server: server)
        token = CredentialStore.credentials(for: keychainKey)?.token
        #if DEBUG
            // A token from the local server, so automated runs start signed in without the browser.
            if let debugToken = ProcessInfo.processInfo.environment["USUALBASE_TOKEN"] { token = debugToken }
        #endif
        if token != nil {
            state = .signedIn
            Task { await refresh() }
        }
    }

    private var keychainKey: String { "account:" + api.server.absoluteString }

    // MARK: - Signing in and out

    func signIn() {
        signInTask?.cancel()
        signInTask = Task {
            do {
                let name = "Usual Base on \(Host.current().localizedName ?? "this Mac")"
                let start = try await api.startConnect(name: name)
                state = .signingIn(code: start.userCode, url: start.verificationUriComplete)
                NSWorkspace.shared.open(start.verificationUriComplete)
                let deadline = Date.now.addingTimeInterval(start.expiresIn)
                while Date.now < deadline {
                    try await Task.sleep(for: .seconds(start.interval))
                    let result = try await api.pollConnect(deviceCode: start.deviceCode)
                    switch result.status {
                    case "pending":
                        continue
                    case "approved":
                        guard let token = result.token else { break }
                        try CredentialStore.save(GitCredentials(username: "usual", token: token), for: keychainKey)
                        self.token = token
                        state = .signedIn
                        didSignIn()
                        await refresh()
                        return
                    case "denied":
                        problem = "Signing in was denied in the browser."
                    default:
                        problem = "The sign-in code expired. Try again."
                    }
                    break
                }
            } catch is CancellationError {
            } catch {
                problem = "Couldn’t sign in: \(error)"
            }
            if case .signingIn = state { state = .signedOut }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        state = .signedOut
    }

    /// Forgets this Mac's token, and revokes it on the server so it can't be used again. Clones stay.
    func signOut() {
        if let token { Task { [api] in try? await api.revokeOwnToken(token) } }
        CredentialStore.delete(for: keychainKey)
        token = nil
        bases = []
        email = nil
        state = .signedOut
    }

    func refresh() async {
        guard let token else { return }
        do {
            async let me = api.me(token: token)
            async let list = api.bases(token: token)
            email = try await me.user.email
            bases = try await list
        } catch AccountAPI.Problem.signedOut {
            signOut()
            problem = AccountAPI.Problem.signedOut.description
        } catch {
            problem = "Couldn’t list your Bases: \(error)"
        }
    }

    /// Creates a Base on the server and adds it to the list.
    func createBase(named name: String) async throws -> HostedBase {
        guard let token else { throw AccountAPI.Problem.signedOut }
        let base = try await api.createBase(named: name, token: token)
        bases.append(base)
        return base
    }

    // MARK: - Git and live updates

    /// The token for a hosted Base's git address; nil for any other remote.
    func credentials(for remoteURL: String) -> GitCredentials? {
        guard let token, baseID(forRemote: remoteURL) != nil else { return nil }
        return GitCredentials(username: "usual", token: token)
    }

    /// The Base's id when `remoteURL` is a hosted Base on this server.
    func baseID(forRemote remoteURL: String) -> String? {
        let prefix = api.server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/git/"
        guard remoteURL.hasPrefix(prefix), remoteURL.hasSuffix(".git") else { return nil }
        return String(remoteURL.dropFirst(prefix.count).dropLast(4))
    }

    func liveUpdates(for remoteURL: String, onPush: @escaping () -> Void, onConnected: @escaping (Bool) -> Void)
        -> LiveUpdates?
    {
        guard let token, let id = baseID(forRemote: remoteURL) else { return nil }
        return LiveUpdates(url: api.eventsURL(for: id), token: token, onPush: onPush, onConnected: onConnected)
    }

    // MARK: - Where clones live

    /// The folder holding this Mac's clones of hosted Bases, chosen once. Agents on this Mac use the same
    /// clones, so their changes show at once.
    func basesFolder() -> URL? {
        if let saved = savedBasesFolder() { return saved }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Use This Folder"
        panel.message =
            "Choose where Usual Base keeps your Bases, for example a new folder “Usual Base” in your home "
            + "folder. Agents on this Mac can use them there too."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return access(url, refresh: true)
    }

    /// The Bases folder, if one was chosen already; never asks.
    func savedBasesFolder() -> URL? {
        if let accessedFolder { return accessedFolder }
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey) else { return nil }
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        else { return nil }
        return access(url, refresh: isStale)
    }

    private func access(_ url: URL, refresh: Bool) -> URL {
        if url.startAccessingSecurityScopedResource() { accessedFolder = url }
        if refresh {
            let data = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.folderKey)
        }
        return url
    }

    /// The Base's clone folder: named after the Base, or after its id too when a different folder has the name.
    func folder(for base: HostedBase, in parent: URL) -> URL {
        let name = base.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let plain = parent.appending(path: name)
        let config = plain.appending(path: ".git/config")
        let exists = FileManager.default.fileExists(atPath: plain.path(percentEncoded: false))
        let isThisBase = (try? String(contentsOf: config, encoding: .utf8))?.contains(base.git) ?? false
        return !exists || isThisBase ? plain : parent.appending(path: "\(name) (\(base.id))")
    }
}
