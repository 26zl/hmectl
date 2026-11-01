import Foundation

public struct Alias: Codable, Sendable, Equatable {
    public let id: String
    public let address: String
    public let label: String
    public let note: String
    public let isActive: Bool
    public let createdAt: Date?
    public let forwardTo: String?

    enum CodingKeys: String, CodingKey {
        case id, address, label, note
        case isActive = "active"
        case createdAt = "created"
        case forwardTo
    }

    public init(
        id: String, address: String, label: String, note: String, isActive: Bool, createdAt: Date?, forwardTo: String?
    ) {
        self.id = id
        self.address = address
        self.label = label
        self.note = note
        self.isActive = isActive
        self.createdAt = createdAt
        self.forwardTo = forwardTo
    }

    /// One entry of Apple's `hmeEmails` list or the `hme` object of a reserve answer.
    init?(json: [String: Any]) {
        guard let id = json["anonymousId"] as? String, let address = json["hme"] as? String else { return nil }
        self.init(
            id: id, address: address, label: json["label"] as? String ?? "", note: json["note"] as? String ?? "",
            isActive: json["isActive"] as? Bool ?? true,
            createdAt: (json["createTimestamp"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000)
            },
            forwardTo: json["forwardToEmail"] as? String
        )
    }
}

/// Apple's Hide My Email web service (`premiummailsettings`).
public struct HideMyEmailClient: Sendable {
    let http: HTTPTransport
    let baseURL: URL
    let query: [String: String]

    /// Asks Apple for a candidate address; nothing is created until it is reserved.
    public func generate() async throws -> String {
        let result = try await call("POST", "/v1/hme/generate")
        guard let address = result["hme"] as? String, AliasInput.isPlausibleAddress(address) else {
            throw HMEError.unexpectedResponse("Apple sent no usable address")
        }
        return address
    }

    public func reserve(address: String, label: String, note: String) async throws -> Alias {
        let result = try await call("POST", "/v1/hme/reserve", body: ["hme": address, "label": label, "note": note])
        guard let alias = (result["hme"] as? [String: Any]).flatMap(Alias.init(json:)) ?? Alias(json: result),
            AliasInput.isPlausibleAddress(alias.address)
        else { throw HMEError.unexpectedResponse("Apple did not confirm the new alias") }
        return alias
    }

    public func list() async throws -> [Alias] {
        let result = try await call("GET", "/v2/hme/list")
        guard let entries = result["hmeEmails"] as? [[String: Any]] else {
            throw HMEError.unexpectedResponse("the alias list is missing")
        }
        return entries.compactMap(Alias.init(json:))
    }

    /// Where mail sent to `alias` goes. Apple's reserve answer leaves it out, so this falls back
    /// to the alias list, which has it per alias and for the account.
    public func forwardingAddress(of alias: Alias) async -> String? {
        if let forwardTo = alias.forwardTo { return forwardTo }
        guard let result = try? await call("GET", "/v2/hme/list") else { return nil }
        let entries = (result["hmeEmails"] as? [[String: Any]])?.compactMap(Alias.init(json:)) ?? []
        return entries.first { $0.id == alias.id }?.forwardTo ?? result["selectedForwardTo"] as? String
    }

    public func setActive(_ active: Bool, id: String) async throws {
        _ = try await call("POST", active ? "/v1/hme/reactivate" : "/v1/hme/deactivate", body: ["anonymousId": id])
    }

    private func call(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var headers = [
            "Accept": "application/json", "User-Agent": AppleWeb.userAgent, "Origin": AppleWeb.origin,
            "Referer": AppleWeb.origin + "/",
        ]
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        if data != nil { headers["Content-Type"] = "application/json" }
        let response = try await http.send(
            HTTPRequest(
                method: method, url: try makeURL(baseURL.absoluteString + path, query), headers: headers, body: data
            )
        )
        return try Self.result(of: response)
    }

    /// The `result` object of an answer, or the error Apple reported.
    static func result(of response: HTTPResponse) throws -> [String: Any] {
        switch response.status {
        case 200..<300:
            break
        case 401 where String(decoding: response.body, as: UTF8.self).contains("Invalid global session"):
            throw HMEError.webAccessDisabled
        case 401, 403, 421, 450:
            throw HMEError.sessionExpired
        default:
            throw HMEError.unexpectedResponse("Hide My Email returned HTTP \(response.status)")
        }
        let json = try jsonObject(response.body)
        if json["success"] as? Bool == false {
            let message = (json["error"] as? [String: Any])?["errorMessage"] as? String
            throw HMEError.apple(message ?? "the request failed")
        }
        return json["result"] as? [String: Any] ?? [:]
    }
}

public enum AliasInput {
    public static let defaultNote = "Created with hmectl"

    public static func label(_ raw: String) throws -> String {
        let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw HMEError.usage("The label must not be empty.") }
        guard label.count <= 100 else { throw HMEError.usage("The label can be at most 100 characters.") }
        guard !hasControlCharacters(label) else {
            throw HMEError.usage("The label must not contain control characters.")
        }
        return label
    }

    public static func note(_ raw: String?) throws -> String {
        guard let raw else { return defaultNote }
        let note = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note.count <= 500 else { throw HMEError.usage("The note can be at most 500 characters.") }
        guard !hasControlCharacters(note) else { throw HMEError.usage("The note must not contain control characters.") }
        return note
    }

    public static func appleID(_ raw: String) throws -> String {
        let appleID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appleID.isEmpty, appleID.count <= 254, !hasControlCharacters(appleID),
            !appleID.contains(where: \.isWhitespace)
        else { throw HMEError.usage("Enter the email address or phone number of your Apple Account.") }
        return appleID
    }

    /// Finds an alias by its address (case-insensitive) or by Apple's anonymous id.
    public static func find(_ target: String, in aliases: [Alias]) -> Alias? {
        let wanted = target.trimmingCharacters(in: .whitespaces)
        return aliases.first { $0.address.caseInsensitiveCompare(wanted) == .orderedSame || $0.id == wanted }
    }

    static func isPlausibleAddress(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return address.count <= 254 && parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !address.contains(where: { $0.isWhitespace }) && !hasControlCharacters(address)
    }

    static func hasControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: TerminalText.isUnsafe)
    }
}
