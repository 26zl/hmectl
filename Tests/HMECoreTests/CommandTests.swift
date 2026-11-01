import Foundation
import Testing

@testable import HMECore

struct CommandTests {
    private func parse(_ arguments: String...) throws -> Invocation {
        try CommandLineParser.parse(arguments)
    }

    @Test func parsesNew() throws {
        #expect(
            try parse("new", "netflix").command
                == .new(label: "netflix", note: nil, copy: true, json: false, dryRun: false)
        )
        #expect(
            try parse("new", "--note=warranty", "--no-copy", "Bike shop", "--json", "--dry-run").command
                == .new(label: "Bike shop", note: "warranty", copy: false, json: true, dryRun: true)
        )
        #expect(
            try parse("new", "--note", "x", "--", "--label-with-dashes").command
                == .new(label: "--label-with-dashes", note: "x", copy: true, json: false, dryRun: false)
        )
    }

    @Test func parsesTheOtherCommands() throws {
        #expect(try parse("list").command == .list(filter: .all, json: false))
        #expect(try parse("list", "--inactive", "--json").command == .list(filter: .inactive, json: true))
        #expect(
            try parse("deactivate", "a@icloud.com").command == .setActive(false, target: "a@icloud.com", dryRun: false))
        #expect(try parse("reactivate", "id1", "--dry-run").command == .setActive(true, target: "id1", dryRun: true))
        #expect(try parse("login", "--apple-id", "me@example.com").command == .login(appleID: "me@example.com"))
        #expect(try parse("logout").command == .logout)
        #expect(try parse("status", "--json").command == .status(json: true))
    }

    @Test func handlesGlobalOptions() throws {
        #expect(try parse().command == .help)
        #expect(try parse("--help").command == .help)
        #expect(try parse("list", "-h").command == .help)
        #expect(try parse("--version").command == .version)
        #expect(try parse("--trace", "list").trace)
        #expect(try !parse("list").trace)
    }

    @Test(arguments: [
        ["bogus"],
        ["new"],
        ["new", "a", "b"],
        ["new", "a", "--active"],
        ["list", "--active", "--inactive"],
        ["list", "extra"],
        ["login", "--note", "x"],
        ["logout", "--json"],
        ["new", "a", "--note"],
        ["new", "a", "--unknown"],
        ["status", "--trace=1"],
    ])
    func rejectsInvalidUsage(arguments: [String]) {
        #expect {
            try CommandLineParser.parse(arguments)
        } throws: { error in
            (error as? HMEError)?.exitCode == 2
        }
    }

    @Test func helpMatchesTheParser() {
        for option in ["--note", "--no-copy", "--json", "--dry-run", "--active", "--inactive", "--apple-id", "--trace"]
        {
            #expect(CommandLineParser.help.contains(option), "\(option) is missing from --help")
        }
        #expect(CommandLineParser.help.contains(Version.current))
    }

    @Test func completionAndReadmeCoverEveryCommandAndOption() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let completion = try String(contentsOf: root.appendingPathComponent("completions/_hmectl"), encoding: .utf8)
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        for command in ["new", "list", "deactivate", "reactivate", "login", "logout", "status"] {
            #expect(completion.contains("'\(command):") || completion.contains("\(command))"), "\(command)")
            #expect(readme.contains("hmectl \(command)"), "README lacks \(command)")
        }
        for option in [
            "--note", "--no-copy", "--json", "--dry-run", "--active", "--inactive", "--apple-id", "--trace", "--help",
            "--version",
        ] {
            #expect(completion.contains(option), "completion lacks \(option)")
            #expect(readme.contains(option), "README lacks \(option)")
        }
    }

    @Test func exitCodesMatchTheDocumentation() {
        #expect(HMEError.usage("x").exitCode == 2)
        #expect(HMEError.notSignedIn.exitCode == 3)
        #expect(HMEError.sessionExpired.exitCode == 3)
        #expect(HMEError.cancelled.exitCode == 4)
        #expect(HMEError.network("x").exitCode == 1)
    }
}
