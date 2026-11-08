import Foundation

/// A remote's address as typed or pasted, checked and with any credentials split off, so that a
/// token never lands in `.git/config`.
public struct RemoteAddress: Equatable, Sendable {
    public let url: String
    /// A token pasted inside the address (`https://user:token@host/…`).
    public let credentials: GitCredentials?

    public enum Problem: Error, Equatable, CustomStringConvertible {
        case empty
        case ssh
        case notHTTPS

        public var description: String {
            switch self {
            case .empty: "Enter the repository’s address."
            case .ssh: "SSH addresses aren’t supported yet. Use the repository’s HTTPS address."
            case .notHTTPS: "Use an address that starts with https://."
            }
        }
    }

    public init(parsing text: String) throws(Problem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        if trimmed.hasPrefix("ssh://") || (!trimmed.contains("://") && trimmed.contains("@")) { throw .ssh }
        // Split off `user:token@` by hand: tokens can hold `?` (Cloudflare Artifacts tokens end
        // in `?expires=…`), which a URL parser reads as the start of a query.
        var address = trimmed
        var userInfo: Substring?
        if let schemeEnd = trimmed.range(of: "://") {
            let rest = trimmed[schemeEnd.upperBound...]
            if let at = rest.indices.last(where: { rest[$0] == "@" && !rest[..<$0].contains("/") }) {
                userInfo = rest[..<at]
                address = String(trimmed[..<schemeEnd.upperBound] + rest[rest.index(after: at)...])
            }
        }
        guard let components = URLComponents(string: address), let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http", components.host?.isEmpty == false
        else { throw .notHTTPS }
        url = address
        if let userInfo, let colon = userInfo.firstIndex(of: ":") {
            let user = String(userInfo[..<colon])
            let token = String(userInfo[userInfo.index(after: colon)...])
            credentials =
                token.isEmpty
                ? nil
                : GitCredentials(
                    username: user.removingPercentEncoding ?? user, token: token.removingPercentEncoding ?? token)
        } else {
            credentials = nil
        }
    }
}
