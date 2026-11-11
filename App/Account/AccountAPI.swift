import Foundation

/// A Base on the hosted service, as its API lists it.
struct HostedBase: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let git: String
    let lastPushAt: Double?
    let lastPushBy: String?
}

/// The hosted Usual Base service's HTTP API: signing in with the device flow, and listing Bases.
struct AccountAPI: Sendable {
    let server: URL

    struct ConnectStart: Decodable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationUriComplete: URL
        let expiresIn: Double
        let interval: Double
    }

    struct ConnectResult: Decodable, Sendable {
        let status: String
        let token: String?
    }

    struct Me: Decodable, Sendable {
        struct User: Decodable, Sendable {
            let name: String
            let email: String
        }
        let user: User
    }

    enum Problem: Error, CustomStringConvertible {
        case signedOut
        case server(String)

        var description: String {
            switch self {
            case .signedOut: "This Mac's sign-in was revoked. Sign in again."
            case .server(let message): message
            }
        }
    }

    private struct ErrorMessage: Decodable { let error: String }

    func startConnect(name: String) async throws -> ConnectStart {
        try await call("/api/connect", body: ["name": name, "kind": "device"])
    }

    func pollConnect(deviceCode: String) async throws -> ConnectResult {
        try await call("/api/connect/token", body: ["device_code": deviceCode])
    }

    func me(token: String) async throws -> Me {
        try await call("/api/me", token: token)
    }

    /// Revokes the token the request is made with, as signing out does.
    func revokeOwnToken(_ token: String) async throws {
        struct Done: Decodable { let revoked: Bool }
        let _: Done = try await call("/api/token/revoke", token: token, body: [:])
    }

    func bases(token: String) async throws -> [HostedBase] {
        struct List: Decodable { let bases: [HostedBase] }
        let list: List = try await call("/api/bases", token: token)
        return list.bases
    }

    func createBase(named name: String, token: String) async throws -> HostedBase {
        struct Created: Decodable { let base: HostedBase }
        let created: Created = try await call("/api/bases", token: token, body: ["name": name])
        return created.base
    }

    /// The WebSocket address for a Base's live updates.
    func eventsURL(for base: String) -> URL {
        var components = URLComponents(
            url: server.appending(path: "api/bases/\(base)/events"), resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        return components.url!
    }

    private func call<T: Decodable>(_ path: String, token: String? = nil, body: [String: String]? = nil) async throws
        -> T
    {
        var request = URLRequest(url: server.appending(path: String(path.dropFirst())))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw Problem.signedOut }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorMessage.self, from: data))?.error
            throw Problem.server(message ?? "The server answered with HTTP \(status).")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
