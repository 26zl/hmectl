import CryptoKit
import Foundation

/// Asks the person at the terminal for verification codes during sign-in.
public protocol SignInPrompter: Sendable {
    /// The code from a trusted Apple device, or nil to get one by text message instead.
    func deviceCode(length: Int, textMessageAvailable: Bool) async throws -> String?
    func textMessageCode(length: Int, phoneHint: String) async throws -> String
    func progress(_ message: String)
}

public enum VerificationCode {
    /// The code without the spaces or dashes people type, if it is exactly `length` ASCII digits.
    public static func normalized(_ input: String, length: Int) -> String? {
        let digits = input.filter { $0 != " " && $0 != "-" }
        return digits.count == length && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber) ? digits : nil
    }
}

/// The iCloud web client's public identifiers. Apple offers no other interface to Hide My Email,
/// so hmectl presents itself the way icloud.com does.
enum AppleWeb {
    static let widgetKey = "d39ba9916b7251055b22c7f910e2ea796ee65e98b2ddecea8f5dde8d9d1a815d"  // gitleaks:allow
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3.1 Safari/605.1.15"
    static let origin = "https://www.icloud.com"
    static let authBase = "https://idmsa.apple.com/appleauth/auth"
    static let setupBase = "https://setup.icloud.com/setup/ws/1"
    static let clientBuildNumber = "2534Project66"
    static let clientMasteringNumber = "2534B22"
    static let accountLockedCode = "-20209"
    static let wrongPasswordCode = "-20101"
}

/// Signs in to an Apple Account and keeps the iCloud web session that Hide My Email needs.
public final class AccountClient: @unchecked Sendable {
    public let http: HTTPTransport
    private var appleID = ""
    private var clientID = ""
    private var authContext: [String: String] = [:]
    private var sessionToken: String?
    private var trustToken: String?
    private var accountCountry: String?
    private var dsid: String?
    private var serviceURL: URL?

    private enum AccountStatus {
        case ready
        case needsSecondFactor
    }

    public init(http: HTTPTransport) {
        self.http = http
    }

    /// Password sign-in with SRP, then two-factor verification when Apple asks for it.
    /// `previous` lets a repeated sign-in to the same account reuse Apple's trust in this client.
    public func signIn(
        appleID: String, password: [UInt8], previous: SessionState?, prompter: SignInPrompter
    ) async throws -> SessionState {
        let sameAccount = previous.map { $0.appleID.caseInsensitiveCompare(appleID) == .orderedSame } ?? false
        self.appleID = appleID
        clientID = sameAccount ? previous!.clientID : UUID().uuidString.lowercased()
        trustToken = sameAccount ? previous?.trustToken : nil
        authContext = [:]
        sessionToken = nil
        accountCountry = nil
        dsid = nil
        serviceURL = nil

        let page = try await authRequest(
            "GET", "/authorize/signin",
            query: [
                "frame_id": clientID, "skVersion": "7", "iframeid": clientID, "client_id": AppleWeb.widgetKey,
                "response_type": "code", "redirect_uri": AppleWeb.origin, "response_mode": "web_message",
                "state": clientID, "authVersion": "latest",
            ]
        )
        guard page.isSuccess else { throw signInFailure(page, passwordChecked: false) }

        var client = try SRPClient<SHA256>.random(group: .rfc5054Bits2048)
        defer { client.discardPrivateKey() }
        let start = try await authRequest(
            "POST", "/signin/init",
            json: [
                "a": Data(client.publicKey.serialized()).base64EncodedString(), "accountName": appleID,
                "protocols": ["s2k", "s2k_fo"],
            ]
        )
        guard start.isSuccess else { throw signInFailure(start, passwordChecked: false) }
        let challenge = try jsonObject(start.body)
        guard let salt = (challenge["salt"] as? String).flatMap({ Data(base64Encoded: $0) }).map(Array.init),
            let serverPublic = (challenge["b"] as? String).flatMap({ Data(base64Encoded: $0) }),
            let iterations = challenge["iteration"] as? Int,
            let passwordProtocol = (challenge["protocol"] as? String).flatMap(AppleSRP.PasswordProtocol.init),
            let token = challenge["c"]
        else { throw HMEError.unexpectedResponse("the sign-in challenge is incomplete") }

        let proofs: (clientProof: [UInt8], serverProof: [UInt8])
        do {
            var key = try AppleSRP.derivedKey(
                password: password, salt: salt, iterations: iterations, protocol: passwordProtocol
            )
            var x = AppleSRP.privateKey(salt: salt, derivedKey: key)
            wipe(&key)
            defer { x.wipe() }
            proofs = try client.proofs(
                identity: Array(appleID.utf8), salt: salt, serverPublicKey: BigUInt(bigEndian: serverPublic), x: x
            )
        } catch is SRPError {
            throw HMEError.unexpectedResponse("the sign-in challenge is not valid SRP")
        }

        let complete = try await authRequest(
            "POST", "/signin/complete", query: ["isRememberMeEnabled": "true"],
            json: [
                "accountName": appleID, "c": token,
                "m1": Data(proofs.clientProof).base64EncodedString(),
                "m2": Data(proofs.serverProof).base64EncodedString(),
                "rememberMe": true, "trustTokens": trustToken.map { [$0] } ?? [],
            ]
        )
        var secondFactorDone = false
        switch complete.status {
        case 200..<300:
            break
        case 409:
            try await verifySecondFactor(prompter: prompter)
            secondFactorDone = true
        default:
            throw signInFailure(complete, passwordChecked: true)
        }

        if try await accountLogin() == .needsSecondFactor {
            guard !secondFactorDone else {
                throw HMEError.unexpectedResponse("iCloud still asks for two-factor authentication after the code")
            }
            try await verifySecondFactor(prompter: prompter)
            guard try await accountLogin() == .ready else {
                throw HMEError.unexpectedResponse("iCloud still asks for two-factor authentication after the code")
            }
        }
        _ = try await hideMyEmail().list()
        return try state()
    }

    /// Restores a saved session and checks it with iCloud, refreshing it from the session token if needed.
    public func resume(_ saved: SessionState) async throws {
        load(saved)
        let validation = try await setupRequest("POST", "/validate", body: Data("null".utf8))
        if validation.isSuccess {
            if try apply(accountData: validation.body) == .ready { return }
        } else if !Self.isAuthFailure(validation.status) {
            throw HMEError.unexpectedResponse("the session check returned HTTP \(validation.status)")
        }
        guard try await accountLogin() == .ready else { throw HMEError.sessionExpired }
    }

    /// Ends the session at Apple. Returns whether Apple confirmed it.
    public func signOut(_ saved: SessionState) async -> Bool {
        load(saved)
        guard let body = try? JSONSerialization.data(withJSONObject: ["trustBrowser": false, "allBrowsers": false]),
            let response = try? await setupRequest(
                "POST", "/logout", query: serviceQuery, body: body, contentType: "text/plain;charset=UTF-8"
            ),
            response.isSuccess, let json = try? jsonObject(response.body)
        else { return false }
        return json["success"] as? Bool == true
    }

    public func hideMyEmail() throws -> HideMyEmailClient {
        guard let serviceURL else { throw HMEError.hideMyEmailUnavailable }
        return HideMyEmailClient(http: http, baseURL: serviceURL, query: serviceQuery)
    }

    /// The current session, including cookies iCloud may have rotated, ready to save.
    public func state(now: Date = Date()) throws -> SessionState {
        guard let sessionToken else { throw HMEError.notSignedIn }
        let cookies = (http.cookieStorage.cookies ?? [])
            .filter { StoredCookie.shouldKeep($0, now: now) }
            .map(StoredCookie.init)
        return SessionState(
            appleID: appleID, clientID: clientID, sessionToken: sessionToken, trustToken: trustToken,
            accountCountry: accountCountry, dsid: dsid, serviceURL: serviceURL?.absoluteString, cookies: cookies,
            savedAt: now
        )
    }

    private func verifySecondFactor(prompter: SignInPrompter) async throws {
        let response = try await authRequest("GET", "", accept: "application/json")
        guard response.isSuccess else {
            throw HMEError.unexpectedResponse("the two-factor options returned HTTP \(response.status)")
        }
        let options = try jsonObject(response.body)
        if options["fsaChallenge"] != nil || !((options["keyNames"] as? [Any]) ?? []).isEmpty {
            throw HMEError.securityKeysUnsupported
        }
        let codeLength = (options["securityCode"] as? [String: Any])?["length"] as? Int ?? 6
        let phone = TrustedPhone.best(in: options)

        if options["noTrustedDevices"] as? Bool != true {
            for attempt in 1...3 {
                guard let code = try await prompter.deviceCode(length: codeLength, textMessageAvailable: phone != nil)
                else { break }
                if try await verifyCode("/verify/trusteddevice/securitycode", ["securityCode": ["code": code]]) {
                    return try await trustSession()
                }
                if attempt == 3 { throw HMEError.invalidCode }
                prompter.progress("Apple did not accept that code. Try again.")
            }
        }

        guard let phone else { throw HMEError.noTrustedPhoneNumber }
        let request = try await authRequest(
            "PUT", "/verify/phone", json: ["phoneNumber": phone.payload, "mode": "sms"])
        guard request.isSuccess else {
            throw HMEError.apple("could not send a text message (HTTP \(request.status)); wait a while and try again")
        }
        for attempt in 1...3 {
            let code = try await prompter.textMessageCode(length: codeLength, phoneHint: phone.hint)
            let verified = try await verifyCode(
                "/verify/phone/securitycode",
                ["phoneNumber": phone.payload, "securityCode": ["code": code], "mode": "sms"]
            )
            if verified { return try await trustSession() }
            if attempt == 3 { break }
            prompter.progress("Apple did not accept that code. Try again.")
        }
        throw HMEError.invalidCode
    }

    /// Apple sometimes answers 409 to a correct code; `securityCode.valid` is the verdict then.
    private func verifyCode(_ path: String, _ body: [String: Any]) async throws -> Bool {
        let response = try await authRequest("POST", path, json: body)
        if response.isSuccess { return true }
        if Self.serviceError(in: response)?.code == AppleWeb.accountLockedCode { throw HMEError.accountLocked }
        if response.status == 409, let json = try? jsonObject(response.body),
            (json["securityCode"] as? [String: Any])?["valid"] as? Bool == true
        {
            return true
        }
        if [400, 401, 403, 409].contains(response.status) { return false }
        throw HMEError.unexpectedResponse("code verification returned HTTP \(response.status)")
    }

    private func trustSession() async throws {
        let response = try await authRequest("GET", "/2sv/trust")
        guard response.isSuccess else {
            throw HMEError.unexpectedResponse("Apple did not trust this session (HTTP \(response.status))")
        }
    }

    private func accountLogin() async throws -> AccountStatus {
        guard let sessionToken else { throw HMEError.sessionExpired }
        let body = try JSONSerialization.data(withJSONObject: [
            "accountCountryCode": accountCountry ?? "", "dsWebAuthToken": sessionToken, "extended_login": true,
            "trustToken": trustToken ?? "",
        ])
        let response = try await setupRequest("POST", "/accountLogin", body: body)
        if Self.isAuthFailure(response.status) { throw HMEError.sessionExpired }
        guard response.isSuccess else {
            throw HMEError.unexpectedResponse("iCloud sign-in returned HTTP \(response.status)")
        }
        return try apply(accountData: response.body)
    }

    private func apply(accountData: Data) throws -> AccountStatus {
        let json = try jsonObject(accountData)
        if json["termsUpdateNeeded"] as? Bool == true { throw HMEError.termsUpdateNeeded }
        if json["hsaChallengeRequired"] as? Bool == true || json["hsaTrustedBrowser"] as? Bool != true {
            return .needsSecondFactor
        }
        guard let dsInfo = json["dsInfo"] as? [String: Any], let accountID = dsInfo["dsid"] else {
            throw HMEError.unexpectedResponse("iCloud sent no account id")
        }
        guard let services = json["webservices"] as? [String: Any],
            let mail = services["premiummailsettings"] as? [String: Any], let address = mail["url"] as? String
        else { throw HMEError.hideMyEmailUnavailable }
        guard let url = HostPolicy.serviceBaseURL(from: address) else {
            throw HMEError.unexpectedResponse("the Hide My Email service is not on an iCloud host")
        }
        dsid = "\(accountID)"
        serviceURL = url
        http.serviceHost = url.host
        return .ready
    }

    private func load(_ saved: SessionState) {
        appleID = saved.appleID
        clientID = saved.clientID
        sessionToken = saved.sessionToken
        trustToken = saved.trustToken
        accountCountry = saved.accountCountry
        dsid = saved.dsid
        if let address = saved.serviceURL, let url = HostPolicy.serviceBaseURL(from: address) {
            serviceURL = url
            http.serviceHost = url.host
        }
        for cookie in saved.cookies.compactMap(\.httpCookie) {
            http.cookieStorage.setCookie(cookie)
        }
    }

    private var serviceQuery: [String: String] {
        var items = [
            "clientBuildNumber": AppleWeb.clientBuildNumber,
            "clientMasteringNumber": AppleWeb.clientMasteringNumber,
            "clientId": clientID,
        ]
        if let dsid { items["dsid"] = dsid }
        return items
    }

    private func authRequest(
        _ method: String, _ path: String, query: [String: String] = [:], json: [String: Any]? = nil,
        accept: String = "application/json, text/javascript"
    ) async throws -> HTTPResponse {
        var headers = [
            "Accept": accept,
            "Content-Type": "application/json",
            "User-Agent": AppleWeb.userAgent,
            "Origin": AppleWeb.origin,
            "Referer": "https://\(HostPolicy.authHost)",
            "X-Apple-OAuth-Client-Id": AppleWeb.widgetKey,
            "X-Apple-OAuth-Client-Type": "firstPartyAuth",
            "X-Apple-OAuth-Redirect-URI": AppleWeb.origin,
            "X-Apple-OAuth-Require-Grant-Code": "true",
            "X-Apple-OAuth-Response-Mode": "web_message",
            "X-Apple-OAuth-Response-Type": "code",
            "X-Apple-OAuth-State": clientID,
            "X-Apple-Widget-Key": AppleWeb.widgetKey,
            "X-Apple-Frame-Id": clientID,
            "X-Apple-FD-Client-Info":
                #"{"U":"\#(AppleWeb.userAgent)","L":"en-US","Z":"GMT+00:00","V":"1.1","F":""}"#,
        ]
        headers.merge(authContext) { _, saved in saved }
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let response = try await http.send(
            HTTPRequest(method: method, url: try makeURL(AppleWeb.authBase + path, query), headers: headers, body: body)
        )
        capture(response)
        return response
    }

    private func setupRequest(
        _ method: String, _ path: String, query: [String: String] = [:], body: Data?,
        contentType: String = "application/json"
    ) async throws -> HTTPResponse {
        let headers = [
            "Accept": "application/json", "Content-Type": contentType, "User-Agent": AppleWeb.userAgent,
            "Origin": AppleWeb.origin, "Referer": AppleWeb.origin + "/",
        ]
        return try await http.send(
            HTTPRequest(
                method: method, url: try makeURL(AppleWeb.setupBase + path, query), headers: headers, body: body)
        )
    }

    private func capture(_ response: HTTPResponse) {
        for header in ["scnt", "X-Apple-ID-Session-Id", "X-Apple-Auth-Attributes"] {
            if let value = response.header(header) { authContext[header] = value }
        }
        if let value = response.header("X-Apple-Session-Token") { sessionToken = value }
        if let value = response.header("X-Apple-TwoSV-Trust-Token") { trustToken = value }
        if let value = response.header("X-Apple-ID-Account-Country") { accountCountry = value }
    }

    /// "Wrong password" only when Apple checked the SRP proof and said so; anything else shows
    /// Apple's own message, so nobody is nudged into trying other passwords.
    private func signInFailure(_ response: HTTPResponse, passwordChecked: Bool) -> HMEError {
        let error = Self.serviceError(in: response)
        if error?.code == AppleWeb.accountLockedCode { return .accountLocked }
        if passwordChecked, [401, 403].contains(response.status),
            error == nil || error?.code == AppleWeb.wrongPasswordCode
        {
            return .wrongCredentials
        }
        if response.status == 412 { return .actionNeededInBrowser }
        if let message = error?.message, !message.isEmpty { return .apple(message) }
        return .unexpectedResponse("sign-in returned HTTP \(response.status)")
    }

    static func serviceError(in response: HTTPResponse) -> (code: String, message: String)? {
        guard let json = try? jsonObject(response.body), let errors = json["serviceErrors"] as? [[String: Any]],
            let first = errors.first
        else { return nil }
        return ("\(first["code"] ?? "")", first["message"] as? String ?? "")
    }

    static func isAuthFailure(_ status: Int) -> Bool {
        [401, 403, 421, 450].contains(status)
    }
}

struct TrustedPhone {
    let payload: [String: Any]
    let hint: String

    /// The phone pyicloud would pick: the top-level choice, then the nested verification data.
    static func best(in options: [String: Any]) -> TrustedPhone? {
        let verification = options["phoneNumberVerification"] as? [String: Any]
        let candidates: [Any?] = [
            options["trustedPhoneNumber"], verification?["trustedPhoneNumber"],
            (verification?["trustedPhoneNumbers"] as? [Any])?.first, (options["trustedPhoneNumbers"] as? [Any])?.first,
        ]
        for case let phone as [String: Any] in candidates {
            guard let id = phone["id"] else { continue }
            var payload: [String: Any] = ["id": id]
            if let nonFTEU = phone["nonFTEU"] as? Bool { payload["nonFTEU"] = nonFTEU }
            let hint = phone["numberWithDialCode"] as? String ?? phone["obfuscatedNumber"] as? String
            return TrustedPhone(payload: payload, hint: hint ?? "your trusted phone number")
        }
        return nil
    }
}

func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else {
        throw HMEError.unexpectedResponse("the response is not a JSON object")
    }
    return dictionary
}

func makeURL(_ address: String, _ query: [String: String]) throws -> URL {
    guard var components = URLComponents(string: address) else {
        throw HMEError.unexpectedResponse("invalid address \(address)")
    }
    if !query.isEmpty {
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let url = components.url else { throw HMEError.unexpectedResponse("invalid address \(address)") }
    return url
}
