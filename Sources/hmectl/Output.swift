import Foundation
import HMECore

enum Output {
    static func clean(_ text: String) -> String {
        TerminalText.clean(text)
    }

    static func table(_ aliases: [Alias]) -> String {
        let rows = aliases.map { alias in
            [
                alias.isActive ? "active" : "inactive", clean(alias.address), clean(alias.label),
                alias.createdAt.map(date) ?? "",
            ]
        }
        let header = ["STATUS", "ALIAS", "LABEL", "CREATED"]
        let widths = header.indices.map { column in
            ([header] + rows).map { $0[column].count }.max() ?? 0
        }
        return ([header] + rows).map { row in
            row.enumerated().map { column, cell in
                column == row.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }

    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return TerminalText.escapingJSON(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    static func json(status summary: KeychainStore.Summary?) throws -> String {
        struct Status: Encodable {
            let signedIn: Bool
            let appleID: String?
            let savedAt: Date?
        }
        return try json(Status(signedIn: summary != nil, appleID: summary?.appleID, savedAt: summary?.modified))
    }

    static func date(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
