import BaseKit
import Foundation
import Security

/// Tokens for git remotes, kept in the login keychain with one item per remote address. They
/// never go into the repository's config.
enum CredentialStore {
    private static let service = "Usual Base git remote"

    static func credentials(for url: String) -> GitCredentials? {
        var query = baseQuery(url)
        query[kSecReturnData] = true
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let item = result as? [CFString: Any],
            let tokenData = item[kSecValueData] as? Data
        else { return nil }
        let usernameData = item[kSecAttrGeneric] as? Data ?? Data()
        return GitCredentials(
            username: String(decoding: usernameData, as: UTF8.self), token: String(decoding: tokenData, as: UTF8.self))
    }

    static func save(_ credentials: GitCredentials, for url: String) throws {
        let attributes: [CFString: Any] = [
            kSecValueData: Data(credentials.token.utf8),
            kSecAttrGeneric: Data(credentials.username.utf8),
            kSecAttrLabel: "Usual Base: \(url)",
        ]
        var status = SecItemUpdate(baseQuery(url) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery(url).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete(for url: String) {
        SecItemDelete(baseQuery(url) as CFDictionary)
    }

    private static func baseQuery(_ url: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: url]
    }

    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}
