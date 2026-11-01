import Darwin
import Foundation
import HMECore

/// Lets only one hmectl command at a time read or write the saved session.
enum SessionLock {
    /// The lock is held until the process exits, which releases it.
    static func acquire() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hmectl.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw failure(path) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return }
        guard errno == EWOULDBLOCK else { throw failure(path) }
        Terminal.error("Waiting for another hmectl command to finish...")
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw failure(path) }
        }
    }

    /// Reads `errno`, so it must come straight after the call that failed.
    private static func failure(_ path: String) -> HMEError {
        .sessionLock("\(path): \(String(cString: strerror(errno)))")
    }
}
