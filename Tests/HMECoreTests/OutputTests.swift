import Foundation
import Testing

@testable import HMECore

struct OutputTests {
    private static let created = Date(timeIntervalSince1970: 1_730_000_000)

    private func column(_ text: String, in line: String) -> Int? {
        line.range(of: text).map { line.distance(from: line.startIndex, to: $0.lowerBound) }
    }

    @Test func alignsTheTableAndCleansApplesText() {
        let lines = Output.table([
            Alias(
                id: "1", address: "quiet_fox_1@icloud.com", label: "Shop\u{1B}[2J", note: "", isActive: true,
                createdAt: nil, forwardTo: nil
            ),
            Alias(
                id: "2", address: "a@icloud.com", label: "Bank", note: "", isActive: false, createdAt: nil,
                forwardTo: nil
            ),
        ]).components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(column("ALIAS", in: lines[0]) == column("quiet_fox_1@icloud.com", in: lines[1]))
        #expect(column("ALIAS", in: lines[0]) == column("a@icloud.com", in: lines[2]))
        #expect(column("LABEL", in: lines[0]) == column("Shop?[2J", in: lines[1]))
        #expect(column("LABEL", in: lines[0]) == column("Bank", in: lines[2]))
        #expect(!lines.joined().unicodeScalars.contains(where: TerminalText.isUnsafe))
    }

    @Test func escapesUnsafeCharactersInJSON() throws {
        let json = try Output.json(
            Alias(
                id: "1", address: "quiet_fox_1@icloud.com", label: "evil\u{202E}\u{9B}", note: "", isActive: true,
                createdAt: Self.created, forwardTo: "me@example.com"
            )
        )
        #expect(json.contains(#""label" : "evil\u202e\u009b""#))
        #expect(json.contains(#""forwardTo" : "me@example.com""#))
        #expect(json.contains(#""created" : "2024-10-27T03:33:20Z""#))
        #expect(!json.unicodeScalars.contains { $0 != "\n" && TerminalText.isUnsafe($0) })
    }

    @Test func describesTheSignInStatusAsJSON() throws {
        #expect(try Output.json(status: nil) == "{\n  \"signedIn\" : false\n}")
        let summary = KeychainStore.Summary(appleID: "user@example.com", modified: Self.created)
        #expect(
            try Output.json(status: summary)
                == "{\n  \"appleID\" : \"user@example.com\",\n  \"savedAt\" : \"2024-10-27T03:33:20Z\",\n  \"signedIn\" : true\n}"
        )
    }
}
