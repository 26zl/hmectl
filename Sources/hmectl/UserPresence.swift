import Foundation
import HMECore
import LocalAuthentication

enum UserPresence {
    /// Touch ID, Apple Watch or the login password before the saved session is used.
    static func confirm(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw HMEError.userPresenceUnavailable(error?.localizedDescription ?? "not available on this Mac")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else if let error = error as? LAError,
                    [.userCancel, .appCancel, .systemCancel, .userFallback].contains(error.code)
                {
                    continuation.resume(throwing: HMEError.cancelled)
                } else {
                    continuation.resume(
                        throwing: HMEError.userPresenceUnavailable(
                            error?.localizedDescription ?? "authentication failed")
                    )
                }
            }
        }
    }
}
