import Foundation
import Security

/// Backend session state persisted across app relaunches.
struct StoredCredentials: Codable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let userID: String
}

enum KeychainTokenStoreError: Error {
    case unhandled(status: OSStatus)
    case decoding(underlying: Error)
}

extension KeychainTokenStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unhandled(let status):
            "キーチェーンの操作に失敗しました。(status: \(status))"
        case .decoding:
            "保存されたログイン情報を読み取れませんでした。"
        }
    }
}

/// Persists `StoredCredentials` in the Keychain rather than UserDefaults, so
/// the backend session survives reinstalls and is never exposed through a
/// plist.
final class KeychainTokenStore {
    private static let service = "com.onikun94.sekisho.backend"
    private static let account = "credentials"

    private let decoder = SekishoJSONCoding.makeDecoder()
    private let encoder = SekishoJSONCoding.makeEncoder()

    func save(_ credentials: StoredCredentials) throws {
        let data = try encoder.encode(credentials)

        var addQuery = Self.baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        guard addStatus == errSecDuplicateItem else {
            throw KeychainTokenStoreError.unhandled(status: addStatus)
        }

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(Self.baseQuery() as CFDictionary, attributesToUpdate as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainTokenStoreError.unhandled(status: updateStatus)
        }
    }

    func load() throws -> StoredCredentials? {
        var query = Self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return nil
            }

            do {
                return try decoder.decode(StoredCredentials.self, from: data)
            } catch {
                throw KeychainTokenStoreError.decoding(underlying: error)
            }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainTokenStoreError.unhandled(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(Self.baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unhandled(status: status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
