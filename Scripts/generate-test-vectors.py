#!/usr/bin/env python3
"""Generate Tests/HMECoreTests/TestVectors.swift.

The vectors come from an independent implementation of the SRP-6a client that
pyicloud uses (pysrp with rfc5054_enable() and no_username_in_x(), SHA-256 and the
RFC 5054 2048-bit group), written with Python's built-in integers. It must reproduce
RFC 5054 Appendix B before anything is written. Standard library only.

Usage: python3 Scripts/generate-test-vectors.py [output-path]
"""

import base64
import hashlib
import pathlib
import random
import sys

N1024 = int(
    "EEAF0AB9ADB38DD69C33F80AFA8FC5E86072618775FF3C0B9EA2314C9C256576"
    "D674DF7496EA81D3383B4813D692C6E0E0D5D8E250B98BE48E495C1D6089DAD1"
    "5DC7D7B46154D6B6CE8EF4AD69B15D4982559B297BCF1885C529F566660E57EC"
    "68EDBC3C05726CC02FD4CBF4976EAA9AFD5138FE8376435B9FC61D2FC0EB06E3",
    16,
)
N2048 = int(
    "AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050"
    "A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50"
    "E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B8"
    "55F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773B"
    "CA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748"
    "544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6"
    "AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB6"
    "94B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73",
    16,
)
G = 2


def minimal(n: int) -> bytes:
    """Big-endian bytes without leading zeros, like pysrp's long_to_bytes."""
    return n.to_bytes((n.bit_length() + 7) // 8, "big")


def padded(n: int, width: int) -> bytes:
    return n.to_bytes(width, "big")


def digest(hash_fn, *parts: bytes) -> bytes:
    h = hash_fn()
    for part in parts:
        h.update(part)
    return h.digest()


def as_int(data: bytes) -> int:
    return int.from_bytes(data, "big")


def client(hash_fn, n: int, a: int, b_pub: int, x: int, identity: bytes, salt: bytes) -> dict:
    width = len(minimal(n))
    k = as_int(digest(hash_fn, minimal(n), padded(G, width)))
    a_pub = pow(G, a, n)
    u = as_int(digest(hash_fn, padded(a_pub, width), padded(b_pub, width)))
    s = pow((b_pub - k * pow(G, x, n)) % n, a + u * x, n)
    key = digest(hash_fn, minimal(s))
    h_n = digest(hash_fn, minimal(n))
    h_g = digest(hash_fn, padded(G, width))
    h_ng = bytes(p ^ q for p, q in zip(h_n, h_g))
    m1 = digest(hash_fn, h_ng, digest(hash_fn, identity), salt, minimal(a_pub), minimal(b_pub), key)
    m2 = digest(hash_fn, minimal(a_pub), m1, key)
    return {"k": k, "A": a_pub, "u": u, "S": s, "K": key, "M1": m1, "M2": m2}


def server_b(hash_fn, n: int, b: int, v: int) -> int:
    width = len(minimal(n))
    k = as_int(digest(hash_fn, minimal(n), padded(G, width)))
    return (k * v + pow(G, b, n)) % n


def server_secret(hash_fn, n: int, a_pub: int, b: int, b_pub: int, v: int) -> int:
    width = len(minimal(n))
    u = as_int(digest(hash_fn, padded(a_pub, width), padded(b_pub, width)))
    return pow(a_pub * pow(v, u, n) % n, b, n)


def check_rfc5054() -> None:
    identity, password = b"alice", b"password123"
    salt = bytes.fromhex("BEB25379D1A8581EB5A727673A2441EE")
    a = int("60975527035CF2AD1989806F0407210BC81EDC04E2762A56AFD529DDDA2D4393", 16)
    b = int("E487CB59D31AC550471E81F00F6928E01DDA08E974A004F49E61F5D105284D20", 16)
    x = as_int(digest(hashlib.sha1, salt, digest(hashlib.sha1, identity + b":" + password)))
    v = pow(G, x, N1024)
    b_pub = server_b(hashlib.sha1, N1024, b, v)
    result = client(hashlib.sha1, N1024, a, b_pub, x, identity, salt)
    expected = {
        "k": "7556AA045AEF2CDD07ABAF0F665C3E818913186F",
        "x": "94B7555AABE9127CC58CCF4993DB6CF84D16C124",
        "u": "CE38B9593487DA98554ED47D70A7AE5F462EF019",
        "A": "61D5E490F6F1B79547B0704C436F523DD0E560F0C64115BB72557EC44352E890"
        "3211C04692272D8B2D1A5358A2CF1B6E0BFCF99F921530EC8E39356179EAE45E"
        "42BA92AEACED825171E1E8B9AF6D9C03E1327F44BE087EF06530E69F66615261"
        "EEF54073CA11CF5858F0EDFDFE15EFEAB349EF5D76988A3672FAC47B0769447B",
        "B": "BD0C61512C692C0CB6D041FA01BB152D4916A1E77AF46AE105393011BAF38964"
        "DC46A0670DD125B95A981652236F99D9B681CBF87837EC996C6DA04453728610"
        "D0C6DDB58B318885D7D82C7F8DEB75CE7BD4FBAA37089E6F9C6059F388838E7A"
        "00030B331EB76840910440B1B27AAEAEEB4012B7D7665238A8E3FB004B117B58",
        "S": "B0DC82BABCF30674AE450C0287745E7990A3381F63B387AAF271A10D233861E3"
        "59B48220F7C4693C9AE12B0A6F67809F0876E2D013800D6C41BB59B6D5979B5C"
        "00A172B4A2A5903A0BDCAF8A709585EB2AFAFA8F3499B200210DCC1F10EB3394"
        "3CD67FC88A2F39A4BE5BEC4EC0A3212DC346D7E474B29EDE8A469FFECA686E5A",
    }
    actual = {"k": result["k"], "x": x, "u": result["u"], "A": result["A"], "B": b_pub, "S": result["S"]}
    for name, value in expected.items():
        if actual[name] != int(value, 16):
            sys.exit(f"RFC 5054 Appendix B mismatch for {name}")
    if server_secret(hashlib.sha1, N1024, result["A"], b, b_pub, v) != result["S"]:
        sys.exit("RFC 5054 server and client secrets differ")


def apple_x(password: bytes, salt: bytes, iterations: int, protocol: str) -> tuple[bytes, int]:
    pw_hash = hashlib.sha256(password).digest()
    secret = pw_hash.hex().encode() if protocol == "s2k_fo" else pw_hash
    derived = hashlib.pbkdf2_hmac("sha256", secret, salt, iterations, 32)
    x = as_int(digest(hashlib.sha256, salt, digest(hashlib.sha256, b":" + derived)))
    return derived, x


def apple_vector(rng: random.Random, name: str, protocol: str, *, short_a: bool = False, short_b: bool = False) -> dict:
    account = "user@example.com"
    password = "correct horse battery staple"
    salt = rng.randbytes(16)
    iterations = 20000 + rng.randrange(1000)
    derived, x = apple_x(password.encode(), salt, iterations, protocol)
    v = pow(G, x, N2048)
    while True:
        a = as_int(rng.randbytes(32))
        b = as_int(rng.randbytes(32))
        b_pub = server_b(hashlib.sha256, N2048, b, v)
        a_pub = pow(G, a, N2048)
        if short_a != (len(minimal(a_pub)) < 256) or short_b != (len(minimal(b_pub)) < 256):
            continue
        break
    result = client(hashlib.sha256, N2048, a, b_pub, x, account.encode(), salt)
    if server_secret(hashlib.sha256, N2048, result["A"], b, b_pub, v) != result["S"]:
        sys.exit(f"server and client secrets differ for {name}")
    return {
        "name": name,
        "account": account,
        "password": password,
        "protocol": protocol,
        "salt": salt.hex(),
        "iterations": iterations,
        "a": f"{a:x}",
        "B": f"{b_pub:x}",
        "derivedKey": derived.hex(),
        "x": f"{x:x}",
        "A": base64.b64encode(minimal(result["A"])).decode(),
        "M1": base64.b64encode(result["M1"]).decode(),
        "M2": base64.b64encode(result["M2"]).decode(),
    }


def arithmetic_cases(rng: random.Random) -> list[tuple[int, int]]:
    cases = [
        (0, 1), (1, 1), (5, 7), (2**32 - 1, 2**32 - 1), (2**64, 2**32 + 1),
        (2**128 - 1, 2**64 - 1), (2**4096 - 1, 2**2048 + 1), (N2048 * N2048 - 1, N2048),
        ((2**96) * 0x80000000, 2**64 * 0x80000000 + 1),
    ]
    for bits_a, bits_b in [(64, 32), (256, 64), (1024, 512), (2048, 2048), (4096, 2048), (4000, 33), (3000, 2999)]:
        for _ in range(4):
            a = rng.getrandbits(bits_a) | (1 << (bits_a - 1))
            b = rng.getrandbits(bits_b) | (1 << (bits_b - 1))
            cases.append((a, b))
    for _ in range(6):
        b = (rng.getrandbits(1024) | (1 << 1023)) & ~0xFFFFFFFF
        cases.append((b * rng.getrandbits(1024) + (b - 1), b))
    return cases


def modpow_cases(rng: random.Random) -> list[tuple[int, int, int]]:
    cases = [(2, 0, 7), (0, 5, 7), (3, 4, 1), (2, 10, 1000), (G, 2**255 + 12345, N2048)]
    for _ in range(4):
        cases.append((rng.getrandbits(2048) % N2048, rng.getrandbits(256), N2048))
    for _ in range(3):
        modulus = rng.getrandbits(512) | 1 | (1 << 511)
        cases.append((rng.getrandbits(600), rng.getrandbits(512), modulus))
    return cases


def swift_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(apple: list[dict], arithmetic: list[tuple[int, int]], modpow: list[tuple[int, int, int]]) -> str:
    lines = [
        "// swift-format-ignore-file",
        "// Generated by Scripts/generate-test-vectors.py. Do not edit by hand.",
        "",
        "enum TestVectors {",
        "    struct Arithmetic {",
        "        let a: String",
        "        let b: String",
        "        let product: String",
        "        let quotient: String",
        "        let remainder: String",
        "    }",
        "",
        "    struct ModPow {",
        "        let base: String",
        "        let exponent: String",
        "        let modulus: String",
        "        let result: String",
        "    }",
        "",
        "    struct AppleSRP {",
        "        let name: String",
        "        let account: String",
        "        let password: String",
        "        let passwordProtocol: String",
        "        let salt: String",
        "        let iterations: Int",
        "        let a: String",
        "        let serverPublic: String",
        "        let derivedKey: String",
        "        let x: String",
        "        let clientPublic: String",
        "        let m1: String",
        "        let m2: String",
        "    }",
        "",
        "    static let arithmetic: [Arithmetic] = [",
    ]
    for a, b in arithmetic:
        q, r = divmod(a, b)
        lines.append(
            f"        Arithmetic(a: \"{a:x}\", b: \"{b:x}\", product: \"{a * b:x}\", "
            f"quotient: \"{q:x}\", remainder: \"{r:x}\"),"
        )
    lines += ["    ]", "", "    static let modPow: [ModPow] = ["]
    for base, exponent, modulus in modpow:
        lines.append(
            f"        ModPow(base: \"{base:x}\", exponent: \"{exponent:x}\", modulus: \"{modulus:x}\", "
            f"result: \"{pow(base, exponent, modulus):x}\"),"
        )
    lines += ["    ]", "", "    static let appleSRP: [AppleSRP] = ["]
    for v in apple:
        lines += [
            "        AppleSRP(",
            f"            name: {swift_string(v['name'])},",
            f"            account: {swift_string(v['account'])},",
            f"            password: {swift_string(v['password'])},",
            f"            passwordProtocol: {swift_string(v['protocol'])},",
            f"            salt: \"{v['salt']}\",",
            f"            iterations: {v['iterations']},",
            f"            a: \"{v['a']}\",",
            f"            serverPublic: \"{v['B']}\",",
            f"            derivedKey: \"{v['derivedKey']}\",  // gitleaks:allow (synthetic test password)",
            f"            x: \"{v['x']}\",",
            f"            clientPublic: \"{v['A']}\",",
            f"            m1: \"{v['M1']}\",",
            f"            m2: \"{v['M2']}\"",
            "        ),",
        ]
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def main() -> None:
    check_rfc5054()
    rng = random.Random(20261101)
    apple = [
        apple_vector(rng, "s2k", "s2k"),
        apple_vector(rng, "s2k_fo", "s2k_fo"),
        apple_vector(rng, "s2k with a leading zero byte in A", "s2k", short_a=True),
        apple_vector(rng, "s2k_fo with a leading zero byte in B", "s2k_fo", short_b=True),
    ]
    root = pathlib.Path(__file__).resolve().parent.parent
    output = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Tests/HMECoreTests/TestVectors.swift"
    output.write_text(render(apple, arithmetic_cases(rng), modpow_cases(rng)))
    print(f"RFC 5054 Appendix B reproduced; wrote {output}")


if __name__ == "__main__":
    main()
