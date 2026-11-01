import Testing

@testable import HMECore

struct BigUIntTests {
    @Test func parsesAndPrintsHex() throws {
        #expect(BigUInt(hex: "0")?.isZero == true)
        #expect(BigUInt(hex: "00ff")?.description == "ff")
        #expect(BigUInt(hex: "1234567890abcdef1234")?.description == "1234567890abcdef1234")
        #expect(BigUInt(hex: "xyz") == nil)
        #expect(BigUInt(hex: "") == nil)
    }

    @Test func serializesMinimalAndPadded() throws {
        let value = try #require(BigUInt(hex: "0102"))
        #expect(value.serialized() == [1, 2])
        #expect(value.serialized(paddedTo: 4) == [0, 0, 1, 2])
        #expect(BigUInt.zero.serialized().isEmpty)
        #expect(BigUInt(bigEndian: [0, 0, 7]).serialized() == [7])
    }

    @Test func comparesAndSubtracts() throws {
        let small = BigUInt(5)
        let large = try #require(BigUInt(hex: "100000000"))
        #expect(small < large)
        #expect(!(large < small))
        #expect((large - small).description == "fffffffb")
        #expect((large - large).isZero)
        #expect((large + small).description == "100000005")
    }

    @Test func wipesToZero() throws {
        var value = try #require(BigUInt(hex: "deadbeefcafebabe0123456789"))
        value.wipe()
        #expect(value.isZero)
        #expect(value.serialized().isEmpty)
    }

    @Test(arguments: TestVectors.arithmetic.indices)
    func matchesReferenceArithmetic(index: Int) throws {
        let vector = TestVectors.arithmetic[index]
        let a = try #require(BigUInt(hex: vector.a))
        let b = try #require(BigUInt(hex: vector.b))
        #expect((a * b).description == vector.product)
        let (quotient, remainder) = a.quotientAndRemainder(dividingBy: b)
        #expect(quotient.description == vector.quotient)
        #expect(remainder.description == vector.remainder)
    }

    @Test(arguments: TestVectors.modPow.indices)
    func matchesReferenceModularPower(index: Int) throws {
        let vector = TestVectors.modPow[index]
        let base = try #require(BigUInt(hex: vector.base))
        let exponent = try #require(BigUInt(hex: vector.exponent))
        let modulus = try #require(BigUInt(hex: vector.modulus))
        #expect(base.power(exponent, modulus: modulus).description == vector.result)
    }
}
