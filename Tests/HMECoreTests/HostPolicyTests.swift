import Foundation
import Testing

@testable import HMECore

struct HostPolicyTests {
    @Test(arguments: [
        "https://idmsa.apple.com/appleauth/auth/signin/init",
        "https://setup.icloud.com/setup/ws/1/validate",
        "https://IDMSA.apple.com:443/appleauth/auth",
        "https://p68-maildomainws.icloud.com/v2/hme/list",
    ])
    func allowsAppleHosts(address: String) throws {
        #expect(HostPolicy.allows(try #require(URL(string: address)), serviceHost: "p68-maildomainws.icloud.com"))
    }

    @Test(arguments: [
        "http://idmsa.apple.com/appleauth/auth",
        "https://idmsa.apple.com.evil.example/appleauth",
        "https://evil.example/?next=https://idmsa.apple.com",
        "https://user:secret@idmsa.apple.com/",
        "https://idmsa.apple.com:8443/",
        "https://www.icloud.com/",
        "https://p99-maildomainws.icloud.com/v2/hme/list",
    ])
    func refusesEverythingElse(address: String) throws {
        #expect(!HostPolicy.allows(try #require(URL(string: address)), serviceHost: "p68-maildomainws.icloud.com"))
    }

    @Test func refusesTheServiceHostBeforeICloudAssignsIt() throws {
        let url = try #require(URL(string: "https://p68-maildomainws.icloud.com/v2/hme/list"))
        #expect(!HostPolicy.allows(url, serviceHost: nil))
    }

    @Test func acceptsTheServiceAddressICloudSends() {
        #expect(
            HostPolicy.serviceBaseURL(from: "https://p68-maildomainws.icloud.com:443")?.absoluteString
                == "https://p68-maildomainws.icloud.com"
        )
        #expect(
            HostPolicy.serviceBaseURL(from: "https://P68-MAILDOMAINWS.icloud.com/")?.absoluteString
                == "https://p68-maildomainws.icloud.com"
        )
    }

    @Test(arguments: [
        "http://p68-maildomainws.icloud.com",
        "https://p68-maildomainws.icloud.com.evil.example",
        "https://evilicloud.com",
        "https://icloud.com",
        "https://p68-maildomainws.icloud.com/path",
        "https://p68-maildomainws.icloud.com?x=1",
        "https://p68-maildomainws.icloud.com:8443",
        "https://user@p68-maildomainws.icloud.com",
        "https://-bad.icloud.com",
        "https://a..icloud.com",
        "not a url",
    ])
    func rejectsServiceAddressesOutsideICloud(address: String) {
        #expect(HostPolicy.serviceBaseURL(from: address) == nil)
    }
}

/// Talks to Apple without credentials to check that the TLS policy accepts Apple's real
/// certificates. Run with HMECTL_LIVE_TESTS=1.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HMECTL_LIVE_TESTS"] == "1"))
struct LiveTLSTests {
    @Test(arguments: [
        "https://setup.icloud.com/setup/ws/1/validate",
        "https://idmsa.apple.com/appleauth/auth/authorize/signin",
    ])
    func appleCertificatesPassThePolicy(address: String) async throws {
        let client = HTTPClient(trace: { print($0) })
        let response = try await client.send(
            HTTPRequest(method: "GET", url: try #require(URL(string: address)), headers: ["Accept": "application/json"])
        )
        #expect(response.status > 0)
    }

    @Test func otherHostsAreRefusedBeforeConnecting() async throws {
        let client = HTTPClient()
        await #expect(throws: HMEError.blockedHost("example.com")) {
            _ = try await client.send(HTTPRequest(method: "GET", url: URL(string: "https://example.com/")!))
        }
    }
}
