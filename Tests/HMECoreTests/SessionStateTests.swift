import Foundation
import Testing

@testable import HMECore

struct SessionStateTests {
    private static func cookie(domain: String, secure: Bool = true, expires: Date? = nil) throws -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "X-APPLE-WEBAUTH-TOKEN", .value: "test-value", .domain: domain, .path: "/",
        ]
        if secure { properties[.secure] = "TRUE" }
        if let expires { properties[.expires] = expires }
        return try #require(HTTPCookie(properties: properties))
    }

    @Test func roundTripsThroughJSON() throws {
        let state = SessionState(
            appleID: "user@example.com", clientID: "client", sessionToken: "session", trustToken: "trust",
            accountCountry: "NOR", dsid: "123", serviceURL: "https://p68-maildomainws.icloud.com",
            cookies: [StoredCookie(try Self.cookie(domain: ".icloud.com"))],
            savedAt: Date(timeIntervalSince1970: 1_730_000_000)
        )
        let decoded = try SessionState.decoded(from: try state.encoded())
        #expect(decoded == state)
        #expect(decoded.version == SessionState.currentVersion)
    }

    @Test func treatsUnreadableKeychainDataAsUnreadableSession() throws {
        #expect(throws: HMEError.unreadableSession) { try KeychainStore.decode(Data("garbage".utf8)) }
        var future = SessionState(
            appleID: "user@example.com", clientID: "client", sessionToken: "session", trustToken: nil,
            accountCountry: nil, dsid: nil, serviceURL: nil, cookies: [], savedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(try KeychainStore.decode(try future.encoded()).appleID == "user@example.com")
        future.version = SessionState.currentVersion + 1
        #expect(throws: HMEError.unreadableSession) { try KeychainStore.decode(try future.encoded()) }
    }

    @Test func restoresCookieAttributes() throws {
        let original = try Self.cookie(domain: ".icloud.com", expires: Date(timeIntervalSince1970: 2_000_000_000))
        let restored = try #require(StoredCookie(original).httpCookie)
        #expect(restored.name == original.name)
        #expect(restored.domain == ".icloud.com")
        #expect(restored.isSecure)
        #expect(restored.expiresDate == original.expiresDate)
    }

    @Test func keepsOnlyLiveSecureICloudCookies() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(StoredCookie.shouldKeep(try Self.cookie(domain: ".icloud.com"), now: now))
        #expect(StoredCookie.shouldKeep(try Self.cookie(domain: "p68-maildomainws.icloud.com"), now: now))
        #expect(!StoredCookie.shouldKeep(try Self.cookie(domain: ".apple.com"), now: now))
        #expect(!StoredCookie.shouldKeep(try Self.cookie(domain: "evilicloud.com"), now: now))
        #expect(!StoredCookie.shouldKeep(try Self.cookie(domain: ".icloud.com", secure: false), now: now))
        #expect(
            !StoredCookie.shouldKeep(
                try Self.cookie(domain: ".icloud.com", expires: Date(timeIntervalSince1970: 1_700_000_000)), now: now)
        )
    }
}
