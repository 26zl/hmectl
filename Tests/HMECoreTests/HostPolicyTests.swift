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

/// HTTPClient's own checks; none of them opens a connection.
struct HTTPClientTests {
    @Test func refusesOtherHostsBeforeConnecting() async throws {
        let client = HTTPClient()
        let url = try #require(URL(string: "https://example.com/"))
        await #expect(throws: HMEError.blockedHost("example.com")) {
            _ = try await client.send(HTTPRequest(method: "GET", url: url))
        }
    }

    @Test func refusesTheServiceHostUntilICloudAssignsIt() async throws {
        let client = HTTPClient()
        let url = try #require(URL(string: "https://p68-maildomainws.icloud.com/v2/hme/list"))
        await #expect(throws: HMEError.blockedHost("p68-maildomainws.icloud.com")) {
            _ = try await client.send(HTTPRequest(method: "GET", url: url))
        }
    }

    @Test func neverFollowsRedirects() async throws {
        let client = HTTPClient()
        let url = try #require(URL(string: "https://setup.icloud.com/setup/ws/1/validate"))
        let elsewhere = try #require(URL(string: "https://example.com/"))
        let redirect = try #require(
            HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": elsewhere.absoluteString])
        )
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let next: URLRequest? = await withCheckedContinuation { continuation in
            client.urlSession(
                session, task: task, willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: elsewhere)
            ) { continuation.resume(returning: $0) }
        }
        #expect(next == nil)
    }

    @Test(arguments: [
        NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodClientCertificate,
        NSURLAuthenticationMethodServerTrust,
    ])
    func neverAnswersAChallengeWithoutAServerTrustWithACredential(method: String) async throws {
        let client = HTTPClient()
        let url = try #require(URL(string: "https://idmsa.apple.com/appleauth/auth"))
        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(
                host: "idmsa.apple.com", port: 443, protocol: NSURLProtectionSpaceHTTPS, realm: nil,
                authenticationMethod: method),
            proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil,
            sender: IgnoringChallengeSender()
        )
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: url)
        let (disposition, hasCredential) = await withCheckedContinuation { continuation in
            client.urlSession(session, task: task, didReceive: challenge) { disposition, credential in
                continuation.resume(returning: (disposition, credential != nil))
            }
        }
        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(!hasCredential)
    }
}

private final class IgnoringChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
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
}
