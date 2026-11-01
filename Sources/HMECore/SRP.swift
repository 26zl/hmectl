import CommonCrypto
import CryptoKit
import Foundation
import Security

public struct SRPGroup: Sendable {
    public let prime: BigUInt
    public let generator: BigUInt

    /// The 2048-bit group from RFC 5054 appendix A, which Apple's sign-in uses.
    public static let rfc5054Bits2048 = SRPGroup(
        prime: BigUInt(
            hex: "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050"
                + "A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50"
                + "E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B8"
                + "55F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773B"
                + "CA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748"
                + "544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6"
                + "AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6"
                + "94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73"
        )!,
        generator: BigUInt(2)
    )

    public init(prime: BigUInt, generator: BigUInt) {
        self.prime = prime
        self.generator = generator
    }
}

public enum SRPError: Error, Equatable {
    case invalidServerKey
    case invalidParameters
    case randomGenerationFailed
}

/// SRP-6a client with RFC 5054 padding, computing exactly what pysrp computes after
/// `rfc5054_enable()`, which is the library pyicloud signs in to Apple with.
public struct SRPClient<Hash: HashFunction>: Sendable {
    public let group: SRPGroup
    public let publicKey: BigUInt
    private var privateKey: BigUInt

    public init(group: SRPGroup, privateKey: BigUInt) {
        self.group = group
        self.privateKey = privateKey
        publicKey = group.generator.power(privateKey, modulus: group.prime)
    }

    /// Overwrites the private key once the proofs are computed.
    public mutating func discardPrivateKey() {
        privateKey.wipe()
    }

    /// A client with a fresh 256-bit private key from the system random number generator.
    public static func random(group: SRPGroup) throws -> SRPClient {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw SRPError.randomGenerationFailed }
        let key = BigUInt(bigEndian: bytes)
        wipe(&bytes)
        guard !key.isZero else { throw SRPError.randomGenerationFailed }
        return SRPClient(group: group, privateKey: key)
    }

    private var width: Int { group.prime.serialized().count }

    /// k = H(N | PAD(g))
    public var multiplier: BigUInt {
        BigUInt(bigEndian: Self.hash(group.prime.serialized(), group.generator.serialized(paddedTo: width)))
    }

    /// u = H(PAD(A) | PAD(B))
    public func scrambler(serverPublicKey: BigUInt) -> BigUInt {
        BigUInt(
            bigEndian: Self.hash(publicKey.serialized(paddedTo: width), serverPublicKey.serialized(paddedTo: width))
        )
    }

    /// S = (B - k * g^x) ^ (a + u * x) mod N, after the SRP-6a checks on B and u.
    public func premasterSecret(serverPublicKey: BigUInt, x: BigUInt) throws -> BigUInt {
        let prime = group.prime
        guard !serverPublicKey.isZero, serverPublicKey < prime else { throw SRPError.invalidServerKey }
        let scrambler = scrambler(serverPublicKey: serverPublicKey)
        guard !scrambler.isZero else { throw SRPError.invalidServerKey }
        let verifierTerm = (multiplier * group.generator.power(x, modulus: prime)) % prime
        let base = (serverPublicKey + prime - verifierTerm) % prime
        return base.power(privateKey + scrambler * x, modulus: prime)
    }

    /// M1 = H(H(N) xor H(PAD(g)) | H(I) | s | A | B | K) and M2 = H(A | M1 | K), with K = H(S).
    public func proofs(
        identity: [UInt8], salt: [UInt8], serverPublicKey: BigUInt, x: BigUInt
    ) throws -> (clientProof: [UInt8], serverProof: [UInt8]) {
        var premaster = try premasterSecret(serverPublicKey: serverPublicKey, x: x)
        var secret = premaster.serialized()
        let sessionKey = Self.hash(secret)
        wipe(&secret)
        premaster.wipe()
        let primeHash = Self.hash(group.prime.serialized())
        let generatorHash = Self.hash(group.generator.serialized(paddedTo: width))
        let groupHash = zip(primeHash, generatorHash).map { $0 ^ $1 }
        let clientProof = Self.hash(
            groupHash, Self.hash(identity), salt, publicKey.serialized(), serverPublicKey.serialized(), sessionKey
        )
        let serverProof = Self.hash(publicKey.serialized(), clientProof, sessionKey)
        return (clientProof, serverProof)
    }

    static func hash(_ parts: [UInt8]...) -> [UInt8] {
        var hasher = Hash()
        for part in parts { hasher.update(data: part) }
        return Array(hasher.finalize())
    }
}

/// Apple's password processing for SRP, as pyicloud's `SrpPassword` does it.
public enum AppleSRP {
    public enum PasswordProtocol: String, Sendable {
        case s2k
        case s2kFO = "s2k_fo"
    }

    /// PBKDF2-HMAC-SHA256 over SHA-256(password), hex encoded first for `s2k_fo`.
    public static func derivedKey(
        password: [UInt8], salt: [UInt8], iterations: Int, protocol passwordProtocol: PasswordProtocol
    ) throws -> [UInt8] {
        guard !salt.isEmpty, (1...10_000_000).contains(iterations) else { throw SRPError.invalidParameters }
        var digest = Array(SHA256.hash(data: password))
        var secret = passwordProtocol == .s2kFO ? lowercaseHex(digest) : digest
        wipe(&digest)
        defer { wipe(&secret) }

        var key = [UInt8](repeating: 0, count: 32)
        let keyCount = key.count
        let status = key.withUnsafeMutableBytes { keyBuffer in
            secret.withUnsafeBytes { secretBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        secretBuffer.baseAddress!.assumingMemoryBound(to: CChar.self), secretBuffer.count,
                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        keyBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self), keyCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw SRPError.invalidParameters }
        return key
    }

    /// x = H(s | H(":" | key)), pysrp's `gen_x` after `no_username_in_x()`.
    public static func privateKey(salt: [UInt8], derivedKey: [UInt8]) -> BigUInt {
        let inner = SRPClient<SHA256>.hash(Array(":".utf8), derivedKey)
        return BigUInt(bigEndian: SRPClient<SHA256>.hash(salt, inner))
    }

    /// ASCII lowercase hex as bytes, so the secret never passes through a String that cannot be wiped.
    private static func lowercaseHex(_ bytes: [UInt8]) -> [UInt8] {
        let digits = Array("0123456789abcdef".utf8)
        var characters: [UInt8] = []
        characters.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            characters.append(digits[Int(byte >> 4)])
            characters.append(digits[Int(byte & 0x0F)])
        }
        return characters
    }
}

/// Overwrites a buffer that held secret material; best effort, since Swift may have copied it.
public func wipe(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = memset_s(base, buffer.count, 0, buffer.count)
    }
}
