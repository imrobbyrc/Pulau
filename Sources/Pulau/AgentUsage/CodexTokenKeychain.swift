import Foundation
import Security

public enum CodexKeychainError: Error {
    case status(OSStatus)
    case invalidData
}

public struct CodexTokenKeychain: Sendable {
    private let service = "com.robby.Pulau.codex"
    public init() {}

    public func save(_ tokens: CodexTokens) throws {
        let record = Record(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken,
                            expiresAt: tokens.expiresAt.timeIntervalSince1970)
        let data = try JSONEncoder().encode(record)
        try put(data.base64EncodedString(), account: "credentials")
    }

    public func load() throws -> CodexTokens? {
        if let encoded = try get("credentials") {
            guard let data = Data(base64Encoded: encoded),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.expiresAt.isFinite, !record.accessToken.isEmpty, !record.refreshToken.isEmpty,
                  let accountID = CodexAuth.accountID(from: record.accessToken) else { throw CodexKeychainError.invalidData }
            return CodexTokens(accessToken: record.accessToken, refreshToken: record.refreshToken,
                               expiresAt: Date(timeIntervalSince1970: record.expiresAt), accountID: accountID)
        }
        let access = try get("access-token")
        let refresh = try get("refresh-token")
        let expiry = try get("expires-at")
        if access == nil && refresh == nil && expiry == nil { return nil }
        guard let access, let refresh, let expiry, let seconds = TimeInterval(expiry), seconds.isFinite,
              let accountID = CodexAuth.accountID(from: access) else { throw CodexKeychainError.invalidData }
        let tokens = CodexTokens(accessToken: access, refreshToken: refresh,
                                 expiresAt: Date(timeIntervalSince1970: seconds), accountID: accountID)
        try save(tokens)
        return tokens
    }

    public func delete() throws {
        for account in ["access-token", "refresh-token", "expires-at", "credentials"] {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw CodexKeychainError.status(status) }
        }
    }

    private struct Record: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func put(_ value: String, account: String) throws {
        let q = query(account)
        let data = Data(value.utf8)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw CodexKeychainError.status(added) }
        } else if status != errSecSuccess { throw CodexKeychainError.status(status) }
    }

    private func get(_ account: String) throws -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CodexKeychainError.status(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw CodexKeychainError.invalidData }
        return value
    }
}
