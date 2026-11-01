import Darwin

/// Arbitrary-precision unsigned integer with just the operations SRP-6a needs.
public struct BigUInt: Sendable, Equatable, Comparable, CustomStringConvertible {
    /// Little-endian 32-bit limbs without trailing zero limbs; zero has no limbs.
    private(set) var limbs: [UInt32]

    public static let zero = BigUInt(limbs: [])
    public static let one = BigUInt(limbs: [1])

    init(limbs: [UInt32]) {
        var trimmed = limbs
        while trimmed.last == 0 { trimmed.removeLast() }
        self.limbs = trimmed
    }

    /// Overwrites the value with zeros; best effort, as copies made by arithmetic are not reached.
    public mutating func wipe() {
        limbs.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
        limbs = []
    }

    public init(_ value: UInt64) {
        self.init(limbs: [UInt32(truncatingIfNeeded: value), UInt32(truncatingIfNeeded: value >> 32)])
    }

    /// Reads big-endian bytes; leading zero bytes are ignored.
    public init(bigEndian bytes: some Collection<UInt8>) {
        var limbs: [UInt32] = []
        limbs.reserveCapacity((bytes.count + 3) / 4)
        var current: UInt32 = 0
        var shift: UInt32 = 0
        for byte in bytes.reversed() {
            current |= UInt32(byte) << shift
            shift += 8
            if shift == 32 {
                limbs.append(current)
                current = 0
                shift = 0
            }
        }
        if shift > 0 { limbs.append(current) }
        self.init(limbs: limbs)
    }

    public init?(hex: String) {
        var digits = Array(hex.utf8)
        guard !digits.isEmpty else { return nil }
        if digits.count % 2 == 1 { digits.insert(UInt8(ascii: "0"), at: 0) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = Self.hexValue(digits[index]), let low = Self.hexValue(digits[index + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        self.init(bigEndian: bytes)
    }

    public var isZero: Bool { limbs.isEmpty }

    public var bitWidth: Int {
        guard let top = limbs.last else { return 0 }
        return limbs.count * 32 - top.leadingZeroBitCount
    }

    /// Minimal big-endian encoding, as pysrp's `long_to_bytes`; zero encodes as no bytes.
    public func serialized() -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(limbs.count * 4)
        for limb in limbs.reversed() {
            bytes.append(UInt8(truncatingIfNeeded: limb >> 24))
            bytes.append(UInt8(truncatingIfNeeded: limb >> 16))
            bytes.append(UInt8(truncatingIfNeeded: limb >> 8))
            bytes.append(UInt8(truncatingIfNeeded: limb))
        }
        guard let first = bytes.firstIndex(where: { $0 != 0 }) else { return [] }
        return Array(bytes[first...])
    }

    /// Big-endian encoding left-padded with zero bytes to exactly `length` bytes.
    public func serialized(paddedTo length: Int) -> [UInt8] {
        let bytes = serialized()
        precondition(bytes.count <= length, "BigUInt does not fit in \(length) bytes")
        return [UInt8](repeating: 0, count: length - bytes.count) + bytes
    }

    public var description: String {
        let bytes = serialized()
        guard !bytes.isEmpty else { return "0" }
        let hex = bytes.map { String($0, radix: 16) }.map { $0.count == 1 ? "0" + $0 : $0 }.joined()
        return hex.first == "0" ? String(hex.dropFirst()) : hex
    }

    func testBit(_ index: Int) -> Bool {
        let limb = index / 32
        guard limb < limbs.count else { return false }
        return (limbs[limb] >> UInt32(index % 32)) & 1 == 1
    }

    public static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
        for index in lhs.limbs.indices.reversed() where lhs.limbs[index] != rhs.limbs[index] {
            return lhs.limbs[index] < rhs.limbs[index]
        }
        return false
    }

    public static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        let (long, short) = lhs.limbs.count >= rhs.limbs.count ? (lhs.limbs, rhs.limbs) : (rhs.limbs, lhs.limbs)
        var result: [UInt32] = []
        result.reserveCapacity(long.count + 1)
        var carry: UInt64 = 0
        for index in long.indices {
            let sum = UInt64(long[index]) + UInt64(index < short.count ? short[index] : 0) + carry
            result.append(UInt32(truncatingIfNeeded: sum))
            carry = sum >> 32
        }
        if carry > 0 { result.append(UInt32(carry)) }
        return BigUInt(limbs: result)
    }

    /// Subtraction; the caller guarantees `lhs >= rhs`.
    public static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        precondition(lhs >= rhs, "BigUInt subtraction would underflow")
        var result = lhs.limbs
        var borrow: Int64 = 0
        for index in result.indices {
            var difference = Int64(result[index]) - Int64(index < rhs.limbs.count ? rhs.limbs[index] : 0) - borrow
            borrow = 0
            if difference < 0 {
                difference += 1 << 32
                borrow = 1
            }
            result[index] = UInt32(difference)
        }
        return BigUInt(limbs: result)
    }

    public static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        if lhs.isZero || rhs.isZero { return .zero }
        var result = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for i in lhs.limbs.indices {
            let digit = UInt64(lhs.limbs[i])
            if digit == 0 { continue }
            var carry: UInt64 = 0
            for j in rhs.limbs.indices {
                let product = digit * UInt64(rhs.limbs[j]) + UInt64(result[i + j]) + carry
                result[i + j] = UInt32(truncatingIfNeeded: product)
                carry = product >> 32
            }
            result[i + rhs.limbs.count] = UInt32(carry)
        }
        return BigUInt(limbs: result)
    }

    public static func % (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        lhs.quotientAndRemainder(dividingBy: rhs).remainder
    }

    /// Long division (Knuth, TAOCP vol. 2, algorithm D) on 32-bit digits.
    public func quotientAndRemainder(dividingBy divisor: BigUInt) -> (quotient: BigUInt, remainder: BigUInt) {
        precondition(!divisor.isZero, "BigUInt division by zero")
        if self < divisor { return (.zero, self) }

        let n = divisor.limbs.count
        if n == 1 {
            let digit = UInt64(divisor.limbs[0])
            var quotient = [UInt32](repeating: 0, count: limbs.count)
            var remainder: UInt64 = 0
            for index in limbs.indices.reversed() {
                let current = remainder << 32 | UInt64(limbs[index])
                quotient[index] = UInt32(truncatingIfNeeded: current / digit)
                remainder = current % digit
            }
            return (BigUInt(limbs: quotient), BigUInt(remainder))
        }

        let m = limbs.count
        let shift = divisor.limbs[n - 1].leadingZeroBitCount
        var vn = [UInt32](repeating: 0, count: n)
        for index in stride(from: n - 1, to: 0, by: -1) {
            vn[index] = divisor.limbs[index] << shift | divisor.limbs[index - 1] >> (32 - shift)
        }
        vn[0] = divisor.limbs[0] << shift
        var un = [UInt32](repeating: 0, count: m + 1)
        un[m] = limbs[m - 1] >> (32 - shift)
        for index in stride(from: m - 1, to: 0, by: -1) {
            un[index] = limbs[index] << shift | limbs[index - 1] >> (32 - shift)
        }
        un[0] = limbs[0] << shift

        let base: UInt64 = 1 << 32
        let vTop = UInt64(vn[n - 1])
        let vNext = UInt64(vn[n - 2])
        var quotient = [UInt32](repeating: 0, count: m - n + 1)
        for j in stride(from: m - n, through: 0, by: -1) {
            let numerator = UInt64(un[j + n]) << 32 | UInt64(un[j + n - 1])
            var qhat = numerator / vTop
            var rhat = numerator % vTop
            while qhat >= base || qhat * vNext > (rhat << 32 | UInt64(un[j + n - 2])) {
                qhat -= 1
                rhat += vTop
                if rhat >= base { break }
            }

            var borrow: Int64 = 0
            for index in 0..<n {
                let product = qhat * UInt64(vn[index])
                let difference = Int64(un[index + j]) - borrow - Int64(product & 0xFFFF_FFFF)
                un[index + j] = UInt32(truncatingIfNeeded: difference)
                borrow = Int64(product >> 32) - (difference >> 32)
            }
            let top = Int64(un[j + n]) - borrow
            un[j + n] = UInt32(truncatingIfNeeded: top)

            if top < 0 {
                qhat -= 1
                var carry: UInt64 = 0
                for index in 0..<n {
                    let sum = UInt64(un[index + j]) + UInt64(vn[index]) + carry
                    un[index + j] = UInt32(truncatingIfNeeded: sum)
                    carry = sum >> 32
                }
                un[j + n] = un[j + n] &+ UInt32(truncatingIfNeeded: carry)
            }
            quotient[j] = UInt32(truncatingIfNeeded: qhat)
        }

        var remainder = [UInt32](repeating: 0, count: n)
        for index in 0..<(n - 1) {
            remainder[index] = un[index] >> shift | un[index + 1] << (32 - shift)
        }
        remainder[n - 1] = un[n - 1] >> shift
        return (BigUInt(limbs: quotient), BigUInt(limbs: remainder))
    }

    /// `self` raised to `exponent`, modulo `modulus`, by left-to-right square-and-multiply.
    public func power(_ exponent: BigUInt, modulus: BigUInt) -> BigUInt {
        precondition(!modulus.isZero, "BigUInt modulus is zero")
        if modulus == .one { return .zero }
        let base = self % modulus
        var result = BigUInt.one
        for bit in stride(from: exponent.bitWidth - 1, through: 0, by: -1) {
            result = (result * result) % modulus
            if exponent.testBit(bit) { result = (result * base) % modulus }
        }
        return result
    }

    private static func hexValue(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
