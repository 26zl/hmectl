import Foundation
import Security

public struct HTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    /// Header names are lowercased.
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// What the account and Hide My Email clients need from the network; tests substitute a fake.
public protocol HTTPTransport: AnyObject, Sendable {
    var cookieStorage: HTTPCookieStorage { get }
    var serviceHost: String? { get set }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// URLSession wrapper that enforces `HostPolicy`, never follows redirects, keeps cookies
/// in memory only and accepts TLS only when the chain ends in a root built into macOS.
public final class HTTPClient: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    public typealias Trace = @Sendable (String) -> Void

    public let cookieStorage: HTTPCookieStorage
    private let trace: Trace?
    private let lock = NSLock()
    private var session: URLSession!
    private var allowedServiceHost: String?
    private var refusedCertificateHost: String?

    public init(trace: Trace? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.waitsForConnectivity = false
        guard let storage = configuration.httpCookieStorage else {
            preconditionFailure("An ephemeral URLSession configuration always has a cookie store")
        }
        cookieStorage = storage
        self.trace = trace
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// The Hide My Email host iCloud assigned to this account; requests to it are allowed.
    public var serviceHost: String? {
        get { lock.withLock { allowedServiceHost } }
        set { lock.withLock { allowedServiceHost = newValue?.lowercased() } }
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard HostPolicy.allows(request.url, serviceHost: serviceHost) else {
            throw HMEError.blockedHost(request.url.host ?? request.url.absoluteString)
        }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let host = request.url.host ?? ""
        trace?("-> \(request.method) https://\(host)\(request.url.path)")
        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            if let refused = lock.withLock({ refusedCertificateHost }) {
                throw HMEError.untrustedCertificate(refused)
            }
            throw HMEError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HMEError.unexpectedResponse("not an HTTP response")
        }
        trace?("<- \(httpResponse.statusCode) \(host) (\(Int(Date().timeIntervalSince(started) * 1000)) ms)")

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let name = key as? String, let value = value as? String {
                headers[name.lowercased()] = value
            }
        }
        return HTTPResponse(status: httpResponse.statusCode, headers: headers, body: data)
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if TLSPolicy.trustsWithBuiltInRoot(trust, host: space.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            lock.withLock { refusedCertificateHost = space.host }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

enum TLSPolicy {
    /// The system's normal evaluation for `host`, plus a chain that ends in a root built
    /// into macOS, so a root added by a user, a profile or a security product is not enough.
    static func trustsWithBuiltInRoot(_ trust: SecTrust, host: String) -> Bool {
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
            SecTrustEvaluateWithError(trust, nil),
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let root = chain.last
        else { return false }
        return builtInRoots.contains(SecCertificateCopyData(root) as Data)
    }

    static let builtInRoots: Set<Data> = {
        var anchors: CFArray?
        guard SecTrustCopyAnchorCertificates(&anchors) == errSecSuccess,
            let certificates = anchors as? [SecCertificate]
        else { return [] }
        return Set(certificates.map { SecCertificateCopyData($0) as Data })
    }()
}
