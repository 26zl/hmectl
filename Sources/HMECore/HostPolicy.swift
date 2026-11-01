import Foundation

/// The only hosts hmectl may contact: Apple's sign-in service, iCloud setup, and the
/// Hide My Email host that iCloud assigns to the account.
public enum HostPolicy {
    public static let authHost = "idmsa.apple.com"
    public static let setupHost = "setup.icloud.com"

    public static func allows(_ url: URL, serviceHost: String?) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
            let host = url.host?.lowercased(), url.port == nil || url.port == 443
        else { return false }
        return host == authHost || host == setupHost || host == serviceHost
    }

    /// The Hide My Email base URL from iCloud's service list, accepted only as a bare
    /// `https://<name>.icloud.com` origin.
    public static func serviceBaseURL(from string: String) -> URL? {
        guard let components = URLComponents(string: string), components.scheme == "https",
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil,
            components.port == nil || components.port == 443,
            components.path.isEmpty || components.path == "/",
            let host = components.host?.lowercased(), isICloudSubdomain(host)
        else { return nil }
        var origin = URLComponents()
        origin.scheme = "https"
        origin.host = host
        return origin.url
    }

    static func isICloudSubdomain(_ host: String) -> Bool {
        let suffix = ".icloud.com"
        guard host.hasSuffix(suffix), host.count > suffix.count else { return false }
        let labels = host.dropLast(suffix.count).split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
