public enum Version {
    public static let current = "0.1.0"
}

public enum ListFilter: Sendable, Equatable {
    case all, active, inactive
}

public enum Command: Sendable, Equatable {
    case help
    case version
    case new(label: String, note: String?, copy: Bool, json: Bool, dryRun: Bool)
    case list(filter: ListFilter, json: Bool)
    case setActive(Bool, target: String, dryRun: Bool)
    case login(appleID: String?)
    case logout
    case status(json: Bool)
}

public struct Invocation: Sendable, Equatable {
    public var command: Command
    public var trace: Bool
}

public enum CommandLineParser {
    public static let help = """
        hmectl \(Version.current): create and manage iCloud+ Hide My Email aliases from the terminal.

        USAGE
          hmectl new <label> [--note <text>] [--no-copy] [--json] [--dry-run]
          hmectl list [--active | --inactive] [--json]
          hmectl deactivate <alias | id> [--dry-run]
          hmectl reactivate <alias | id> [--dry-run]
          hmectl login [--apple-id <apple-account>]
          hmectl logout
          hmectl status [--json]

        COMMANDS
          new         Create an alias, label it and copy it to the clipboard.
          list        List your aliases, newest first.
          deactivate  Stop forwarding mail sent to an alias.
          reactivate  Forward mail sent to an alias again.
          login       Sign in with your password and a verification code.
          logout      Sign out at Apple and delete the saved session.
          status      Show which account is signed in, without contacting Apple.

        OPTIONS
          --note <text>   Note stored with a new alias (default: "Created with hmectl").
          --no-copy       Do not copy the new alias to the clipboard.
          --json          Print machine-readable JSON.
          --dry-run       Show what would change and change nothing (new does not contact Apple).
          --active        List only active aliases.
          --inactive      List only inactive aliases.
          --apple-id      Apple Account to sign in with (asked for when left out).
          --trace         Print each request (method, host and path) to stderr.
          -h, --help      Show this help.
          --version       Show the version.

        new, list, deactivate, reactivate and logout ask for Touch ID or your login password before
        they use the saved session; login asks for your Apple Account password instead.

        EXIT STATUS
          0 success, 1 error, 2 usage error, 3 not signed in or session expired, 4 cancelled

        EXAMPLES
          hmectl new netflix
          hmectl new "Bike shop" --note "Warranty registration"
          hmectl deactivate abc_123@icloud.com
        """

    private static let flagOptions: Set<String> = [
        "--trace", "--help", "-h", "--version", "--json", "--no-copy", "--dry-run", "--active", "--inactive",
    ]
    private static let valueOptions: Set<String> = ["--note", "--apple-id"]

    public static func parse(_ arguments: [String]) throws -> Invocation {
        var flags = Set<String>()
        var values: [String: String] = [:]
        var positionals: [String] = []
        var optionsEnded = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if optionsEnded || !argument.hasPrefix("-") || argument == "-" {
                positionals.append(argument)
            } else if argument == "--" {
                optionsEnded = true
            } else if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                let name = String(argument[..<equals])
                guard valueOptions.contains(name) else { throw usage("Unknown option \(name).") }
                values[name] = String(argument[argument.index(after: equals)...])
            } else if valueOptions.contains(argument) {
                guard index < arguments.count else { throw usage("\(argument) needs a value.") }
                let value = arguments[index]
                guard !value.hasPrefix("-") || value == "-" else {
                    throw usage("\(argument) needs a value; use \(argument)=<text> for text that starts with '-'.")
                }
                values[argument] = value
                index += 1
            } else if flagOptions.contains(argument) {
                flags.insert(argument)
            } else {
                throw usage("Unknown option \(argument).")
            }
        }

        let trace = flags.contains("--trace")
        if flags.contains("--help") || flags.contains("-h") { return Invocation(command: .help, trace: trace) }
        if flags.contains("--version") { return Invocation(command: .version, trace: trace) }
        guard let name = positionals.first else { return Invocation(command: .help, trace: trace) }
        let operands = Array(positionals.dropFirst())

        func accept(_ allowedFlags: Set<String>, values allowedValues: Set<String> = [], operands count: Int) throws {
            if let flag = flags.subtracting(allowedFlags.union(["--trace"])).sorted().first {
                throw usage("\(flag) does not apply to '\(name)'.")
            }
            if let option = Set(values.keys).subtracting(allowedValues).sorted().first {
                throw usage("\(option) does not apply to '\(name)'.")
            }
            guard operands.count == count else {
                throw usage(count == 0 ? "'\(name)' takes no arguments." : "'\(name)' needs exactly \(count) argument.")
            }
        }

        let command: Command
        switch name {
        case "new":
            try accept(["--no-copy", "--json", "--dry-run"], values: ["--note"], operands: 1)
            command = .new(
                label: operands[0], note: values["--note"], copy: !flags.contains("--no-copy"),
                json: flags.contains("--json"), dryRun: flags.contains("--dry-run")
            )
        case "list":
            try accept(["--json", "--active", "--inactive"], operands: 0)
            if flags.contains("--active") && flags.contains("--inactive") {
                throw usage("Use either --active or --inactive.")
            }
            let filter: ListFilter =
                flags.contains("--active") ? .active : flags.contains("--inactive") ? .inactive : .all
            command = .list(filter: filter, json: flags.contains("--json"))
        case "deactivate", "reactivate":
            try accept(["--dry-run"], operands: 1)
            command = .setActive(name == "reactivate", target: operands[0], dryRun: flags.contains("--dry-run"))
        case "login":
            try accept([], values: ["--apple-id"], operands: 0)
            command = .login(appleID: values["--apple-id"])
        case "logout":
            try accept([], operands: 0)
            command = .logout
        case "status":
            try accept(["--json"], operands: 0)
            command = .status(json: flags.contains("--json"))
        case "help":
            command = .help
        default:
            throw usage("Unknown command '\(name)'.")
        }
        return Invocation(command: command, trace: trace)
    }

    private static func usage(_ message: String) -> HMEError {
        .usage("\(message) Run 'hmectl --help' for usage.")
    }
}
