import Foundation
import Testing

@testable import HMECore

/// Replays scripted answers per "METHOD path" and enforces the same host policy as HTTPClient.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    let cookieStorage: HTTPCookieStorage = URLSessionConfiguration.ephemeral.httpCookieStorage!
    private let lock = NSLock()
    private var host: String?
    private var routes: [String: [Result<HTTPResponse, HMEError>]]
    private var log: [HTTPRequest] = []

    init(_ routes: [String: [Result<HTTPResponse, HMEError>]]) {
        self.routes = routes
    }

    var serviceHost: String? {
        get { lock.withLock { host } }
        set { lock.withLock { host = newValue } }
    }

    var requests: [HTTPRequest] { lock.withLock { log } }

    func requests(to key: String) -> [HTTPRequest] {
        requests.filter { "\($0.method) \($0.url.path)" == key }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard HostPolicy.allows(request.url, serviceHost: serviceHost) else {
            throw HMEError.blockedHost(request.url.host ?? "")
        }
        let key = "\(request.method) \(request.url.path)"
        let answer: Result<HTTPResponse, HMEError>? = lock.withLock {
            log.append(request)
            guard var queue = routes[key], !queue.isEmpty else { return nil }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[key] = queue
            return next
        }
        guard let answer else { throw HMEError.unexpectedResponse("no scripted answer for \(key)") }
        return try answer.get()
    }
}

struct ScriptedPrompter: SignInPrompter {
    var deviceCode: String?
    var textMessageCode = "654321"

    func deviceCode(length: Int, textMessageAvailable: Bool) async throws -> String? { deviceCode }
    func textMessageCode(length: Int, phoneHint: String) async throws -> String { textMessageCode }
    func progress(_ message: String) {}
}

struct AccountClientTests {
    static let password = "correct horse battery staple"

    static func reply(_ status: Int, _ json: Any = [String: Any](), headers: [String: String] = [:])
        -> Result<HTTPResponse, HMEError>
    {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let lowercased = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        return .success(HTTPResponse(status: status, headers: lowercased, body: body))
    }

    static var challenge: [String: Any] {
        [
            "salt": Data(repeating: 7, count: 16).base64EncodedString(),
            "b": Data([0x5A] + [UInt8](repeating: 0x33, count: 255)).base64EncodedString(),
            "iteration": 1000, "protocol": "s2k", "c": "challenge-token",
        ]
    }

    static var trustedAccount: [String: Any] {
        [
            "dsInfo": ["dsid": "123456"], "hsaTrustedBrowser": true,
            "webservices": [
                "premiummailsettings": ["url": "https://p68-maildomainws.icloud.com:443", "status": "active"]
            ],
        ]
    }

    static var twoFactorOptions: [String: Any] {
        [
            "securityCode": ["length": 6],
            "trustedPhoneNumbers": [["id": 1, "numberWithDialCode": "+47 ••• •• •12", "pushMode": "sms"]],
        ]
    }

    /// Routes for a sign-in that ends with two-factor verification and a trusted session.
    static func signInRoutes(complete: Result<HTTPResponse, HMEError>) -> [String: [Result<HTTPResponse, HMEError>]] {
        [
            "GET /appleauth/auth/authorize/signin": [reply(200, headers: ["scnt": "scnt-1"])],
            "POST /appleauth/auth/signin/init": [reply(200, challenge)],
            "POST /appleauth/auth/signin/complete": [complete],
            "GET /appleauth/auth": [reply(200, twoFactorOptions)],
            "PUT /appleauth/auth/verify/phone": [reply(200)],
            "POST /appleauth/auth/verify/phone/securitycode": [reply(409, ["securityCode": ["valid": true]])],
            "POST /appleauth/auth/verify/trusteddevice/securitycode": [reply(204)],
            "GET /appleauth/auth/2sv/trust": [
                reply(204, headers: ["X-Apple-TwoSV-Trust-Token": "trust-1", "X-Apple-Session-Token": "session-2"])
            ],
            "POST /setup/ws/1/accountLogin": [reply(200, trustedAccount)],
            "GET /v2/hme/list": [reply(200, ["success": true, "result": ["hmeEmails": [Any]()]])],
        ]
    }

    static let twoFactorRequired = reply(
        409, ["authType": "hsa2"], headers: ["X-Apple-Session-Token": "session-1", "X-Apple-ID-Account-Country": "NOR"]
    )

    private func signIn(_ transport: FakeTransport, prompter: ScriptedPrompter = ScriptedPrompter()) async throws
        -> SessionState
    {
        try await AccountClient(http: transport).signIn(
            appleID: "user@example.com", password: Array(Self.password.utf8), previous: nil, prompter: prompter
        )
    }

    @Test func signsInWithATextMessageCode() async throws {
        let transport = FakeTransport(Self.signInRoutes(complete: Self.twoFactorRequired))
        let state = try await signIn(transport)

        #expect(state.sessionToken == "session-2")
        #expect(state.trustToken == "trust-1")
        #expect(state.accountCountry == "NOR")
        #expect(state.dsid == "123456")
        #expect(state.serviceURL == "https://p68-maildomainws.icloud.com")
        #expect(transport.requests(to: "POST /appleauth/auth/signin/complete").count == 1)

        let start = try #require(transport.requests(to: "POST /appleauth/auth/signin/init").first?.body)
        let startJSON = try #require(try JSONSerialization.jsonObject(with: start) as? [String: Any])
        #expect(startJSON["accountName"] as? String == "user@example.com")
        #expect(startJSON["protocols"] as? [String] == ["s2k", "s2k_fo"])

        let verify = try #require(transport.requests(to: "POST /appleauth/auth/verify/phone/securitycode").first)
        let verifyJSON = try #require(try JSONSerialization.jsonObject(with: verify.body ?? Data()) as? [String: Any])
        #expect(verifyJSON["mode"] as? String == "sms")
        #expect((verifyJSON["securityCode"] as? [String: Any])?["code"] as? String == "654321")
        #expect(verify.headers["scnt"] == "scnt-1")
    }

    @Test func neverSendsThePassword() async throws {
        let transport = FakeTransport(Self.signInRoutes(complete: Self.twoFactorRequired))
        _ = try await signIn(transport)
        for request in transport.requests {
            let text = String(decoding: request.body ?? Data(), as: UTF8.self) + request.url.absoluteString
            #expect(!text.contains(Self.password))
            #expect(!text.contains(Data(Self.password.utf8).base64EncodedString()))
        }
    }

    @Test func acceptsADeviceCodeThatAppleConfirmsWith409() async throws {
        var routes = Self.signInRoutes(complete: Self.twoFactorRequired)
        routes["POST /appleauth/auth/verify/trusteddevice/securitycode"] = [
            Self.reply(409, ["securityCode": ["valid": true]])
        ]
        let transport = FakeTransport(routes)
        _ = try await signIn(transport, prompter: ScriptedPrompter(deviceCode: "123456"))
        #expect(transport.requests(to: "PUT /appleauth/auth/verify/phone").isEmpty)
    }

    @Test func reportsAWrongPasswordOnceWithoutRetrying() async throws {
        let transport = FakeTransport(
            Self.signInRoutes(
                complete: Self.reply(401, ["serviceErrors": [["code": "-20101", "message": "Incorrect password."]]])
            )
        )
        await #expect(throws: HMEError.wrongCredentials) { _ = try await signIn(transport) }
        #expect(transport.requests(to: "POST /appleauth/auth/signin/complete").count == 1)
    }

    @Test func doesNotCallEarlierFailuresAWrongPassword() async throws {
        var routes = Self.signInRoutes(complete: Self.twoFactorRequired)
        routes["POST /appleauth/auth/signin/init"] = [
            Self.reply(401, ["serviceErrors": [["code": "-20283", "message": "Too many attempts."]]])
        ]
        let transport = FakeTransport(routes)
        await #expect(throws: HMEError.apple("Too many attempts.")) { _ = try await signIn(transport) }
        #expect(transport.requests(to: "POST /appleauth/auth/signin/complete").isEmpty)
    }

    @Test func showsApplesMessageForOtherRejections() async throws {
        let transport = FakeTransport(
            Self.signInRoutes(
                complete: Self.reply(403, ["serviceErrors": [["code": "-20751", "message": "Account disabled."]]])
            )
        )
        await #expect(throws: HMEError.apple("Account disabled.")) { _ = try await signIn(transport) }
    }

    @Test func recognisesALockedAccount() async throws {
        let transport = FakeTransport(
            Self.signInRoutes(complete: Self.reply(403, ["serviceErrors": [["code": "-20209", "message": "Locked."]]]))
        )
        await #expect(throws: HMEError.accountLocked) { _ = try await signIn(transport) }
    }

    @Test func asksForASecondFactorWhenICloudWantsOneAfterSignIn() async throws {
        var routes = Self.signInRoutes(
            complete: Self.reply(200, headers: ["X-Apple-Session-Token": "session-1"])
        )
        routes["POST /setup/ws/1/accountLogin"] = [
            Self.reply(200, ["hsaChallengeRequired": true, "hsaTrustedBrowser": false]),
            Self.reply(200, Self.trustedAccount),
        ]
        let transport = FakeTransport(routes)
        let state = try await signIn(transport, prompter: ScriptedPrompter(deviceCode: "123456"))
        #expect(state.trustToken == "trust-1")
        #expect(transport.requests(to: "POST /setup/ws/1/accountLogin").count == 2)
    }

    @Test func refusesAServiceHostOutsideICloud() async throws {
        var routes = Self.signInRoutes(complete: Self.twoFactorRequired)
        var account = Self.trustedAccount
        account["webservices"] = ["premiummailsettings": ["url": "https://evil.example"]]
        routes["POST /setup/ws/1/accountLogin"] = [Self.reply(200, account)]
        let transport = FakeTransport(routes)
        await #expect(throws: HMEError.unexpectedResponse("the Hide My Email service is not on an iCloud host")) {
            _ = try await signIn(transport)
        }
    }

    private static let saved = SessionState(
        appleID: "user@example.com", clientID: "client-1", sessionToken: "session-1", trustToken: "trust-1",
        accountCountry: "NOR", dsid: "123456", serviceURL: "https://p68-maildomainws.icloud.com", cookies: [],
        savedAt: Date(timeIntervalSince1970: 1_730_000_000)
    )

    @Test func resumesWithAValidSession() async throws {
        let transport = FakeTransport(["POST /setup/ws/1/validate": [Self.reply(200, Self.trustedAccount)]])
        let client = AccountClient(http: transport)
        try await client.resume(Self.saved)
        #expect(transport.requests(to: "POST /setup/ws/1/accountLogin").isEmpty)
        #expect(transport.serviceHost == "p68-maildomainws.icloud.com")
    }

    @Test func refreshesAnExpiredWebSessionFromTheSessionToken() async throws {
        let transport = FakeTransport([
            "POST /setup/ws/1/validate": [Self.reply(421)],
            "POST /setup/ws/1/accountLogin": [Self.reply(200, Self.trustedAccount)],
        ])
        try await AccountClient(http: transport).resume(Self.saved)
        let login = try #require(transport.requests(to: "POST /setup/ws/1/accountLogin").first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: login) as? [String: Any])
        #expect(json["dsWebAuthToken"] as? String == "session-1")
        #expect(json["trustToken"] as? String == "trust-1")
    }

    @Test(arguments: [421, 401])
    func reportsAnExpiredSession(status: Int) async throws {
        let transport = FakeTransport([
            "POST /setup/ws/1/validate": [Self.reply(421)],
            "POST /setup/ws/1/accountLogin": [Self.reply(status)],
        ])
        await #expect(throws: HMEError.sessionExpired) { try await AccountClient(http: transport).resume(Self.saved) }
    }

    @Test func reportsAnUntrustedSessionAsExpired() async throws {
        let transport = FakeTransport([
            "POST /setup/ws/1/validate": [Self.reply(200, ["hsaChallengeRequired": true])],
            "POST /setup/ws/1/accountLogin": [Self.reply(200, ["hsaChallengeRequired": true])],
        ])
        await #expect(throws: HMEError.sessionExpired) { try await AccountClient(http: transport).resume(Self.saved) }
    }

    @Test func keepsNetworkErrorsApartFromExpiry() async throws {
        let transport = FakeTransport(["POST /setup/ws/1/validate": [.failure(HMEError.network("offline"))]])
        await #expect(throws: HMEError.network("offline")) {
            try await AccountClient(http: transport).resume(Self.saved)
        }
    }

    @Test func reportsUnexpectedServerErrors() async throws {
        let transport = FakeTransport(["POST /setup/ws/1/validate": [Self.reply(500)]])
        await #expect(throws: HMEError.unexpectedResponse("the session check returned HTTP 500")) {
            try await AccountClient(http: transport).resume(Self.saved)
        }
    }

    @Test func signsOutAtAppleAndUntrustsThisClient() async throws {
        let transport = FakeTransport(["POST /setup/ws/1/logout": [Self.reply(200, ["success": true])]])
        #expect(await AccountClient(http: transport).signOut(Self.saved))
        let request = try #require(transport.requests(to: "POST /setup/ws/1/logout").first)
        #expect(request.headers["Content-Type"] == "text/plain;charset=UTF-8")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Bool])
        #expect(body == ["trustBrowser": false, "allBrowsers": false])
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "clientId", value: "client-1")))
        #expect(query.contains(URLQueryItem(name: "dsid", value: "123456")))
    }

    @Test(arguments: [
        AccountClientTests.reply(421), AccountClientTests.reply(200, ["success": false]),
        .failure(HMEError.network("offline")),
    ])
    func reportsASignOutAppleDidNotConfirm(answer: Result<HTTPResponse, HMEError>) async {
        let transport = FakeTransport(["POST /setup/ws/1/logout": [answer]])
        #expect(await AccountClient(http: transport).signOut(Self.saved) == false)
    }

    @Test func normalizesTypedVerificationCodes() {
        #expect(VerificationCode.normalized("123456", length: 6) == "123456")
        #expect(VerificationCode.normalized("123 456", length: 6) == "123456")
        #expect(VerificationCode.normalized("12-34-56", length: 6) == "123456")
        #expect(VerificationCode.normalized("12345", length: 6) == nil)
        #expect(VerificationCode.normalized("12345a", length: 6) == nil)
        #expect(VerificationCode.normalized("١٢٣٤٥٦", length: 6) == nil)
    }
}
