import Darwin
import Foundation
import HMECore

enum Terminal {
    /// Whether a controlling terminal exists for prompts, even when stdin or stdout is redirected.
    static var isInteractive: Bool {
        let descriptor = open("/dev/tty", O_RDWR)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data((Output.clean(message) + "\n").utf8))
    }

    static func line(_ prompt: String) throws -> String {
        var bytes = try read(prompt, echo: true)
        defer { wipe(&bytes) }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    static func secret(_ prompt: String) throws -> [UInt8] {
        try read(prompt, echo: false)
    }

    /// Reads from the terminal with readpassphrase(3), which restores echo if interrupted.
    private static func read(_ prompt: String, echo: Bool) throws -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 1024)
        defer { _ = memset_s(&buffer, buffer.count, 0, buffer.count) }
        let flags = RPP_REQUIRE_TTY | (echo ? RPP_ECHO_ON : RPP_ECHO_OFF)
        guard readpassphrase(Output.clean(prompt), &buffer, buffer.count, flags) != nil else {
            throw HMEError.needsTerminal
        }
        let length = strnlen(buffer, buffer.count)
        return buffer[..<length].map { UInt8(bitPattern: $0) }
    }
}
