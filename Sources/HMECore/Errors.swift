import Foundation

public enum HMEError: Error, Equatable, CustomStringConvertible {
    case usage(String)
    case notSignedIn
    case sessionExpired
    case cancelled
    case needsTerminal
    case wrongCredentials
    case accountLocked
    case actionNeededInBrowser
    case invalidCode
    case securityKeysUnsupported
    case noTrustedPhoneNumber
    case termsUpdateNeeded
    case webAccessDisabled
    case hideMyEmailUnavailable
    case aliasNotFound(String)
    case blockedHost(String)
    case untrustedCertificate(String)
    case network(String)
    case apple(String)
    case unexpectedResponse(String)
    case keychain(String)
    case keychainAccessDenied
    case unreadableSession
    case duplicateSessions
    case sessionLock(String)
    case userPresenceUnavailable(String)

    /// 0 success, 1 failure, 2 usage error, 3 sign-in required, 4 cancelled.
    public var exitCode: Int32 {
        switch self {
        case .usage: 2
        case .notSignedIn, .sessionExpired, .unreadableSession: 3
        case .cancelled, .keychainAccessDenied: 4
        default: 1
        }
    }

    public var description: String {
        switch self {
        case .usage(let message):
            message
        case .notSignedIn:
            "Not signed in. Run 'hmectl login' first."
        case .sessionExpired:
            "Your iCloud session has expired. Run 'hmectl login' to sign in again."
        case .cancelled:
            "Cancelled."
        case .needsTerminal:
            "Signing in needs an interactive terminal for the password and the verification code."
        case .wrongCredentials:
            "Apple did not accept the Apple Account or password. hmectl does not retry, so the account is not locked by repeated attempts."
        case .accountLocked:
            "Apple reports that this Apple Account is locked. Unlock it at https://iforgot.apple.com, then try again."
        case .actionNeededInBrowser:
            "Apple wants you to finish a step in a browser first. Sign in once at https://www.icloud.com, then try again."
        case .invalidCode:
            "Apple did not accept the verification code."
        case .securityKeysUnsupported:
            "This Apple Account uses security keys for two-factor authentication, which hmectl does not support."
        case .noTrustedPhoneNumber:
            "Apple offered no trusted phone number to send a text message to."
        case .termsUpdateNeeded:
            "Apple has new iCloud terms. Accept them by signing in once at https://www.icloud.com, then try again."
        case .webAccessDisabled:
            "iCloud refused this session for Hide My Email (\"Invalid global session\"). Run 'hmectl login' again; if that does not help and Advanced Data Protection is on, turn on Access iCloud Data on the Web first."
        case .hideMyEmailUnavailable:
            "Hide My Email is not available for this account. It needs an iCloud+ subscription."
        case .aliasNotFound(let target):
            "No Hide My Email alias matches '\(target)'. Run 'hmectl list' to see your aliases."
        case .blockedHost(let host):
            "Refused to contact \(host): it is not one of the Apple hosts hmectl talks to."
        case .untrustedCertificate(let host):
            "Refused the TLS certificate of \(host): it does not chain to a root certificate built into macOS. A proxy or security product may be intercepting the connection."
        case .network(let message):
            "Network error: \(message)"
        case .apple(let message):
            "Apple: \(message)"
        case .unexpectedResponse(let message):
            "Unexpected response from Apple: \(message)"
        case .keychain(let message):
            "Keychain error: \(message)"
        case .keychainAccessDenied:
            "The Keychain did not allow access to the saved session (access denied or wrong Keychain password)."
        case .unreadableSession:
            "The saved session cannot be read. Run 'hmectl logout' to delete it, then 'hmectl login'."
        case .duplicateSessions:
            "Your login Keychain holds more than one hmectl session, and hmectl saves only one, so another program may have added it. Run 'hmectl logout' to delete them all, then 'hmectl login'."
        case .sessionLock(let message):
            "Could not lock the saved session (\(message)), so hmectl stops rather than risk two commands overwriting it."
        case .userPresenceUnavailable(let message):
            "Cannot confirm that it is you (Touch ID or your login password): \(message)"
        }
    }
}
