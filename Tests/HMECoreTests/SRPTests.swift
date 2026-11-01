import CryptoKit
import Foundation
import Testing

@testable import HMECore

struct SRPTests {
    private static let rfc5054Bits1024 = SRPGroup(
        prime: BigUInt(
            hex: "EEAF0AB9ADB38DD69C33F80AFA8FC5E86072618775FF3C0B9EA2314C9C256576"
                + "D674DF7496EA81D3383B4813D692C6E0E0D5D8E250B98BE48E495C1D6089DAD1"
                + "5DC7D7B46154D6B6CE8EF4AD69B15D4982559B297BCF1885C529F566660E57EC"
                + "68EDBC3C05726CC02FD4CBF4976EAA9AFD5138FE8376435B9FC61D2FC0EB06E3"
        )!,
        generator: BigUInt(2)
    )

    /// RFC 5054 appendix B, which uses SHA-1 and the username in x.
    @Test func reproducesRFC5054AppendixB() throws {
        let salt = try #require(BigUInt(hex: "BEB25379D1A8581EB5A727673A2441EE")).serialized()
        let a = try #require(BigUInt(hex: "60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393"))
        let serverPublic = try #require(
            BigUInt(
                hex: "BD0C61512C692C0CB6D041FA01BB152D4916A1E77AF46AE105393011BAF38964"
                    + "DC46A0670DD125B95A981652236F99D9B681CBF87837EC996C6DA04453728610"
                    + "D0C6DDB58B318885D7D82C7F8DEB75CE7BD4FBAA37089E6F9C6059F388838E7A"
                    + "00030B331EB76840910440B1B27AAEAEEB4012B7D7665238A8E3FB004B117B58"
            )
        )
        let inner = SRPClient<Insecure.SHA1>.hash(Array("alice:password123".utf8))
        let x = BigUInt(bigEndian: SRPClient<Insecure.SHA1>.hash(salt, inner))
        #expect(x.description == "94b7555aabe9127cc58ccf4993db6cf84d16c124")

        let client = SRPClient<Insecure.SHA1>(group: Self.rfc5054Bits1024, privateKey: a)
        #expect(client.multiplier.description == "7556aa045aef2cdd07abaf0f665c3e818913186f")
        #expect(
            client.publicKey.description
                == "61d5e490f6f1b79547b0704c436f523dd0e560f0c64115bb72557ec44352e890"
                + "3211c04692272d8b2d1a5358a2cf1b6e0bfcf99f921530ec8e39356179eae45e"
                + "42ba92aeaced825171e1e8b9af6d9c03e1327f44be087ef06530e69f66615261"
                + "eef54073ca11cf5858f0edfdfe15efeab349ef5d76988a3672fac47b0769447b"
        )
        #expect(
            client.scrambler(serverPublicKey: serverPublic).description == "ce38b9593487da98554ed47d70a7ae5f462ef019")
        #expect(
            try client.premasterSecret(serverPublicKey: serverPublic, x: x).description
                == "b0dc82babcf30674ae450c0287745e7990a3381f63b387aaf271a10d233861e3"
                + "59b48220f7c4693c9ae12b0a6f67809f0876e2d013800d6c41bb59b6d5979b5c"
                + "00a172b4a2a5903a0bdcaf8a709585eb2afafa8f3499b200210dcc1f10eb3394"
                + "3cd67fc88a2f39a4be5bec4ec0a3212dc346d7e474b29ede8a469ffeca686e5a"
        )
    }

    @Test(arguments: TestVectors.appleSRP.indices)
    func matchesAppleSignInVectors(index: Int) throws {
        let vector = TestVectors.appleSRP[index]
        let salt = try #require(Self.bytes(hex: vector.salt))
        let passwordProtocol = try #require(AppleSRP.PasswordProtocol(rawValue: vector.passwordProtocol))
        let key = try AppleSRP.derivedKey(
            password: Array(vector.password.utf8), salt: salt, iterations: vector.iterations,
            protocol: passwordProtocol
        )
        #expect(Self.hex(key) == vector.derivedKey, "\(vector.name)")
        let x = AppleSRP.privateKey(salt: salt, derivedKey: key)
        #expect(x.description == vector.x, "\(vector.name)")

        let client = SRPClient<SHA256>(group: .rfc5054Bits2048, privateKey: try #require(BigUInt(hex: vector.a)))
        #expect(Data(client.publicKey.serialized()).base64EncodedString() == vector.clientPublic, "\(vector.name)")
        let proofs = try client.proofs(
            identity: Array(vector.account.utf8), salt: salt,
            serverPublicKey: try #require(BigUInt(hex: vector.serverPublic)), x: x
        )
        #expect(Data(proofs.clientProof).base64EncodedString() == vector.m1, "\(vector.name)")
        #expect(Data(proofs.serverProof).base64EncodedString() == vector.m2, "\(vector.name)")
    }

    @Test func rejectsUnsafeServerKeys() throws {
        let client = try SRPClient<SHA256>.random(group: .rfc5054Bits2048)
        let prime = SRPGroup.rfc5054Bits2048.prime
        #expect(throws: SRPError.invalidServerKey) {
            try client.premasterSecret(serverPublicKey: .zero, x: .one)
        }
        #expect(throws: SRPError.invalidServerKey) {
            try client.premasterSecret(serverPublicKey: prime, x: .one)
        }
        #expect(throws: SRPError.invalidServerKey) {
            try client.premasterSecret(serverPublicKey: prime + .one, x: .one)
        }
    }

    @Test func rejectsUnreasonableDerivationParameters() {
        #expect(throws: SRPError.invalidParameters) {
            try AppleSRP.derivedKey(password: [1], salt: [], iterations: 1000, protocol: .s2k)
        }
        #expect(throws: SRPError.invalidParameters) {
            try AppleSRP.derivedKey(password: [1], salt: [1], iterations: 0, protocol: .s2k)
        }
    }

    @Test func randomClientsDiffer() throws {
        let first = try SRPClient<SHA256>.random(group: .rfc5054Bits2048)
        let second = try SRPClient<SHA256>.random(group: .rfc5054Bits2048)
        #expect(first.publicKey != second.publicKey)
    }

    static func bytes(hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
