import Foundation

/// Everything hmectl keeps between runs. It is stored only as one Keychain item.
public struct SessionState: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var appleID: String
    public var clientID: String
    public var sessionToken: String
    public var trustToken: String?
    public var accountCountry: String?
    public var dsid: String?
    public var serviceURL: String?
    public var cookies: [StoredCookie]
    public var savedAt: Date

    public init(
        appleID: String, clientID: String, sessionToken: String, trustToken: String?, accountCountry: String?,
        dsid: String?, serviceURL: String?, cookies: [StoredCookie], savedAt: Date
    ) {
        version = Self.currentVersion
        self.appleID = appleID
        self.clientID = clientID
        self.sessionToken = sessionToken
        self.trustToken = trustToken
        self.accountCountry = accountCountry
        self.dsid = dsid
        self.serviceURL = serviceURL
        self.cookies = cookies
        self.savedAt = savedAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> SessionState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionState.self, from: data)
    }
}

public struct StoredCookie: Codable, Sendable, Equatable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var expires: Date?
    public var isSecure: Bool
    public var isHTTPOnly: Bool

    public init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
    }

    public var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
        ]
        if let expires { properties[.expires] = expires }
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }

    /// Only iCloud cookies are worth keeping; Apple sign-in cookies are needed during login alone.
    public static func shouldKeep(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        let domain = cookie.domain.lowercased()
        let isICloud = domain == "icloud.com" || domain == ".icloud.com" || domain.hasSuffix(".icloud.com")
        let isLive = cookie.expiresDate.map { $0 > now } ?? true
        return isICloud && isLive && cookie.isSecure
    }
}
