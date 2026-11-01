import Foundation
import Testing

@testable import HMECore

/// Response shapes as Apple's iCloud web client receives them.
struct HideMyEmailTests {
    private static func response(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: [:], body: Data(body.utf8))
    }

    @Test func readsTheAliasList() throws {
        let result = try HideMyEmailClient.result(
            of: Self.response(
                200,
                """
                {"success":true,"timestamp":1730000000,"result":{"forwardToEmails":["me@example.com"],
                "selectedForwardTo":"me@example.com","hmeEmails":[
                {"origin":"ON_DEMAND","anonymousId":"abc123","domain":"","forwardToEmail":"me@example.com",
                 "hme":"quiet_fox_1@icloud.com","label":"Netflix","note":"","createTimestamp":1730000000000,
                 "isActive":true,"recipientMailId":""},
                {"anonymousId":"def456","hme":"slow_owl_2@icloud.com","label":"Shop","isActive":false},
                {"anonymousId":"missing-address"}]}}
                """
            )
        )
        let aliases = (result["hmeEmails"] as? [[String: Any]] ?? []).compactMap(Alias.init(json:))
        #expect(aliases.count == 2)
        #expect(aliases[0].address == "quiet_fox_1@icloud.com")
        #expect(aliases[0].createdAt == Date(timeIntervalSince1970: 1_730_000_000))
        #expect(aliases[1].isActive == false)
        #expect(aliases[1].createdAt == nil)
    }

    @Test func reportsApplesErrorMessage() {
        #expect(throws: HMEError.apple("You have reached the limit of addresses you can create at this time.")) {
            try HideMyEmailClient.result(
                of: Self.response(
                    200,
                    #"{"success":false,"error":{"errorCode":"-41015","errorMessage":"You have reached the limit of addresses you can create at this time."}}"#
                )
            )
        }
    }

    @Test func recognisesBlockedWebAccess() {
        #expect(throws: HMEError.webAccessDisabled) {
            try HideMyEmailClient.result(of: Self.response(401, #"{"reason":"Invalid global session","error":2}"#))
        }
    }

    @Test func treatsOtherAuthFailuresAsExpiry() {
        #expect(throws: HMEError.sessionExpired) {
            try HideMyEmailClient.result(of: Self.response(421, "{}"))
        }
        #expect(throws: HMEError.sessionExpired) {
            try HideMyEmailClient.result(of: Self.response(401, #"{"reason":"Missing token"}"#))
        }
    }

    @Test func refusesNonJSONAnswers() {
        #expect(throws: HMEError.unexpectedResponse("the response is not a JSON object")) {
            try HideMyEmailClient.result(of: Self.response(200, "<html>"))
        }
        #expect(throws: HMEError.unexpectedResponse("Hide My Email returned HTTP 500")) {
            try HideMyEmailClient.result(of: Self.response(500, "{}"))
        }
    }

    @Test func validatesLabelsAndNotes() throws {
        #expect(try AliasInput.label("  Netflix ") == "Netflix")
        #expect(throws: HMEError.self) { try AliasInput.label("") }
        #expect(throws: HMEError.self) { try AliasInput.label("bad\u{1B}[31m") }
        #expect(throws: HMEError.self) { try AliasInput.label(String(repeating: "x", count: 101)) }
        #expect(try AliasInput.note(nil) == AliasInput.defaultNote)
        #expect(try AliasInput.note(" warranty ") == "warranty")
        #expect(throws: HMEError.self) { try AliasInput.note("line\nbreak") }
        #expect(throws: HMEError.self) { try AliasInput.appleID("two words") }
    }

    @Test func findsAliasesByAddressOrID() {
        let aliases = [
            Alias(
                id: "abc123", address: "Quiet_Fox_1@icloud.com", label: "Netflix", note: "", isActive: true,
                createdAt: nil, forwardTo: nil
            )
        ]
        #expect(AliasInput.find("quiet_fox_1@icloud.com", in: aliases)?.id == "abc123")
        #expect(AliasInput.find("abc123", in: aliases)?.address == "Quiet_Fox_1@icloud.com")
        #expect(AliasInput.find("other@icloud.com", in: aliases) == nil)
    }

    @Test func checksGeneratedAddresses() {
        #expect(AliasInput.isPlausibleAddress("quiet_fox_1@icloud.com"))
        #expect(!AliasInput.isPlausibleAddress("no-at-sign"))
        #expect(!AliasInput.isPlausibleAddress("a@b@icloud.com"))
        #expect(!AliasInput.isPlausibleAddress("spa ce@icloud.com"))
    }

    @Test func readsApplesServiceErrors() {
        let error = AccountClient.serviceError(
            in: Self.response(403, #"{"serviceErrors":[{"code":"-20209","message":"Locked."}]}"#))
        #expect(error?.code == "-20209")
        #expect(error?.message == "Locked.")
        #expect(AccountClient.serviceError(in: Self.response(401, "{}")) == nil)
        #expect(AccountClient.serviceError(in: Self.response(401, "<html>")) == nil)
    }

    @Test func picksTheTrustedPhoneNumber() throws {
        let options: [String: Any] = [
            "trustedPhoneNumbers": [["id": 2, "numberWithDialCode": "+47 ••• •• •12", "pushMode": "sms"]],
            "trustedPhoneNumber": [
                "id": 1, "numberWithDialCode": "+47 ••• •• •34", "pushMode": "sms", "nonFTEU": true,
            ],
        ]
        let phone = try #require(TrustedPhone.best(in: options))
        #expect(phone.payload["id"] as? Int == 1)
        #expect(phone.payload["nonFTEU"] as? Bool == true)
        #expect(phone.hint == "+47 ••• •• •34")
        #expect(TrustedPhone.best(in: [:]) == nil)
    }
}
