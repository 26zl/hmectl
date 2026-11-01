import Darwin
import Foundation

/// Lets only one hmectl command at a time read or write the saved session.
enum SessionLock {
    /// The lock is held until the process exits, which releases it.
    static func acquire() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("hmectl.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            Terminal.error("Waiting for another hmectl command to finish...")
            _ = flock(descriptor, LOCK_EX)
        }
    }
}
