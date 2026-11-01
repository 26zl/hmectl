import Foundation
import Security

/// Stores the session as one generic password in the login Keychain. The Keychain gives
/// the binary that created the item silent access; other programs get a prompt.
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "hmectl") {
        self.service = service
    }

    public struct Summary: Sendable {
        public let appleID: String
        public let modified: Date?
    }

    public func load() throws -> SessionState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw HMEError.unreadableSession }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> SessionState {
        guard let state = try? SessionState.decoded(from: data), state.version == SessionState.currentVersion else {
            throw HMEError.unreadableSession
        }
        return state
    }

    /// Account name and modification date, read without touching the secret data.
    public func summary() throws -> Summary? {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let attributes = result as? [String: Any] else { return nil }
        return Summary(
            appleID: attributes[kSecAttrAccount as String] as? String ?? "",
            modified: attributes[kSecAttrModificationDate as String] as? Date
        )
    }

    /// Saves the session. `replacing` deletes any earlier item first, so a fresh login also
    /// refreshes which binary the Keychain trusts with the item.
    public func save(_ state: SessionState, replacing: Bool = false) throws {
        let data = try state.encoded()
        if replacing { try delete() }
        let update: [String: Any] = [kSecAttrAccount as String: state.appleID, kSecValueData as String: data]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecAttrAccount as String] = state.appleID
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "hmectl iCloud session"
            item[kSecAttrComment as String] = "iCloud web session saved by hmectl. Remove it with 'hmectl logout'."
            status = SecItemAdd(item as CFDictionary, nil)
        }
        try check(status)
    }

    @discardableResult
    public func delete() throws -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw HMEError.keychainAccessDenied
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw HMEError.keychain(message)
        }
    }
}
