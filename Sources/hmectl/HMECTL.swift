import Foundation
import HMECore

@main
struct HMECTL {
    static func main() async {
        let code: Int32
        do {
            let invocation = try CommandLineParser.parse(Array(CommandLine.arguments.dropFirst()))
            code = try await Runner(trace: invocation.trace).run(invocation.command)
        } catch let error as HMEError {
            Terminal.error(error.description)
            code = error.exitCode
        } catch {
            Terminal.error(error.localizedDescription)
            code = 1
        }
        exit(code)
    }
}

struct Runner {
    private let account: AccountClient
    private let store = KeychainStore()

    init(trace: Bool) {
        var handler: HTTPClient.Trace?
        if trace {
            handler = { line in Terminal.error("trace: \(line)") }
        }
        account = AccountClient(http: HTTPClient(trace: handler))
    }

    func run(_ command: Command) async throws -> Int32 {
        switch command {
        case .help:
            print(CommandLineParser.help)
            return 0
        case .version:
            print("hmectl \(Version.current)")
            return 0
        case .new(let label, let note, let copy, let json, let dryRun):
            return try await create(label: label, note: note, copy: copy, json: json, dryRun: dryRun)
        case .list(let filter, let json):
            return try await list(filter: filter, json: json)
        case .setActive(let active, let target, let dryRun):
            return try await setActive(active, target: target, dryRun: dryRun)
        case .login(let appleID):
            return try await login(appleID: appleID)
        case .logout:
            return try await logout()
        case .status(let json):
            return try status(json: json)
        }
    }

    private func create(label rawLabel: String, note rawNote: String?, copy: Bool, json: Bool, dryRun: Bool)
        async throws -> Int32
    {
        let label = try AliasInput.label(rawLabel)
        let note = try AliasInput.note(rawNote)
        if dryRun {
            guard try store.summary() != nil else { throw HMEError.notSignedIn }
            if json {
                print(try Output.json(["action": "create", "label": label, "note": note]))
            } else {
                print(
                    "Would create an alias labelled \"\(Output.clean(label))\" with the note \"\(Output.clean(note))\"."
                )
            }
            return 0
        }
        let service = try await openSession()
        defer { saveSession() }
        let address = try await service.generate()
        let alias = try await service.reserve(address: address, label: label, note: note)
        print(json ? try Output.json(alias) : Output.clean(alias.address))
        let copied = copy && Clipboard.copy(alias.address)
        Terminal.error(
            "Created \(alias.address) for \"\(alias.label)\"" + (copied ? " and copied it to the clipboard." : ".")
        )
        if copy && !copied { Terminal.error("Could not copy the alias to the clipboard.") }
        return 0
    }

    private func list(filter: ListFilter, json: Bool) async throws -> Int32 {
        let service = try await openSession()
        defer { saveSession() }
        let aliases = try await service.list()
            .filter { filter == .all || $0.isActive == (filter == .active) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        if json {
            print(try Output.json(aliases))
        } else if aliases.isEmpty {
            Terminal.error("No aliases.")
        } else {
            print(Output.table(aliases))
        }
        return 0
    }

    private func setActive(_ active: Bool, target: String, dryRun: Bool) async throws -> Int32 {
        let service = try await openSession()
        defer { if !dryRun { saveSession() } }
        let aliases = try await service.list()
        guard let alias = AliasInput.find(target, in: aliases) else { throw HMEError.aliasNotFound(target) }
        if alias.isActive == active {
            Terminal.error("\(alias.address) is already \(active ? "active" : "inactive").")
            return 0
        }
        if dryRun {
            let verb = active ? "reactivate" : "deactivate"
            print("Would \(verb) \(Output.clean(alias.address)) (\"\(Output.clean(alias.label))\").")
            return 0
        }
        try await service.setActive(active, id: alias.id)
        Terminal.error("\(active ? "Reactivated" : "Deactivated") \(alias.address).")
        return 0
    }

    private func login(appleID rawAppleID: String?) async throws -> Int32 {
        guard Terminal.isInteractive else { throw HMEError.needsTerminal }
        SessionLock.acquire()
        let saved = try store.summary()
        let appleID = try AliasInput.appleID(rawAppleID ?? Terminal.line("Apple Account (email or phone number): "))
        if let saved, saved.appleID.caseInsensitiveCompare(appleID) != .orderedSame {
            throw HMEError.usage("Already signed in as \(saved.appleID). Run 'hmectl logout' first.")
        }
        var password = try Terminal.secret("Password for \(appleID): ")
        defer { wipe(&password) }
        guard !password.isEmpty else { throw HMEError.usage("The password must not be empty.") }

        // The earlier session is read only after the password, and only for Apple's trust in this client.
        var previous: SessionState?
        if saved != nil {
            do {
                previous = try store.load()
            } catch HMEError.unreadableSession {
                previous = nil
            }
        }
        Terminal.error("Signing in to Apple...")
        let state = try await account.signIn(
            appleID: appleID, password: password, previous: previous, prompter: TerminalPrompter()
        )
        try store.save(state, replacing: true)
        Terminal.error(
            "Signed in as \(appleID). The session is saved in your login Keychain; 'hmectl logout' removes it.")
        return 0
    }

    private func logout() async throws -> Int32 {
        SessionLock.acquire()
        guard try store.summary() != nil else {
            Terminal.error("Not signed in.")
            return 0
        }
        var confirmed = false
        do {
            if let state = try store.load() { confirmed = await account.signOut(state) }
        } catch HMEError.unreadableSession {
            Terminal.error("The saved session cannot be read, so it cannot be ended at Apple.")
        }
        try store.delete()
        Terminal.error(
            confirmed
                ? "Signed out at Apple and deleted the saved session."
                : "Deleted the saved session. Apple did not confirm the sign-out; the session ends when it expires, or sooner with Sign Out of All Browsers at icloud.com."
        )
        return 0
    }

    private func status(json: Bool) throws -> Int32 {
        let summary = try store.summary()
        if json {
            print(try Output.json(status: summary))
        } else if let summary {
            let saved = summary.modified.map { " (session saved \(Output.dateTime($0)))" } ?? ""
            print("Signed in as \(Output.clean(summary.appleID))\(saved).")
        } else {
            print("Not signed in.")
        }
        return summary == nil ? 3 : 0
    }

    /// Touch ID or the login password, then the saved session, checked with iCloud.
    private func openSession() async throws -> HideMyEmailClient {
        SessionLock.acquire()
        guard try store.summary() != nil else { throw HMEError.notSignedIn }
        try await UserPresence.confirm(reason: "use your saved iCloud session for Hide My Email")
        guard let state = try store.load() else { throw HMEError.notSignedIn }
        try await account.resume(state)
        return try account.hideMyEmail()
    }

    /// Keeps cookies iCloud rotated during the command; failing to save is not fatal.
    private func saveSession() {
        do {
            try store.save(account.state())
        } catch {
            Terminal.error("Could not update the saved session: \(error)")
        }
    }
}

struct TerminalPrompter: SignInPrompter {
    func deviceCode(length: Int, textMessageAvailable: Bool) async throws -> String? {
        Terminal.error(
            "If a sign-in request appears on one of your Apple devices, choose Allow and enter the code it shows.")
        if textMessageAvailable { Terminal.error("Press Return without a code to get one by text message instead.") }
        while true {
            let input = try Terminal.line("Verification code: ")
            if input.isEmpty {
                if textMessageAvailable { return nil }
                continue
            }
            if let code = Self.normalized(input, length: length) { return code }
            Terminal.error("Enter the \(length)-digit code.")
        }
    }

    func textMessageCode(length: Int, phoneHint: String) async throws -> String {
        Terminal.error("Apple is sending a code by text message to \(phoneHint).")
        while true {
            if let code = Self.normalized(try Terminal.line("Verification code: "), length: length) { return code }
            Terminal.error("Enter the \(length)-digit code.")
        }
    }

    func progress(_ message: String) {
        Terminal.error(message)
    }

    static func normalized(_ input: String, length: Int) -> String? {
        let digits = input.filter { $0 != " " && $0 != "-" }
        return digits.count == length && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber) ? digits : nil
    }
}
