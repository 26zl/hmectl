import Testing

@testable import HMECore

struct TerminalTextTests {
    @Test func replacesControlAndBidiCharacters() {
        #expect(TerminalText.clean("a\u{1B}[31mb") == "a?[31mb")
        #expect(TerminalText.clean("x\u{9B}31m") == "x?31m")
        #expect(TerminalText.clean("pay\u{202E}fdp.exe") == "pay?fdp.exe")
        #expect(TerminalText.clean("del\u{7F}") == "del?")
    }

    @Test func keepsOrdinaryTextAndEmoji() {
        #expect(TerminalText.clean("Café 🚲 👨‍👩‍👧") == "Café 🚲 👨‍👩‍👧")
    }

    @Test func escapesWhatJSONEncoderLeavesRaw() {
        #expect(
            TerminalText.escapingJSON("{\n  \"label\" : \"x\u{9B}y\u{202E}\"\n}")
                == "{\n  \"label\" : \"x\\u009by\\u202e\"\n}")
    }

    @Test func rejectsUnsafeLabels() {
        #expect(throws: HMEError.self) { try AliasInput.label("evil\u{202E}") }
        #expect(throws: HMEError.self) { try AliasInput.label("evil\u{9B}") }
        #expect(throws: Never.self) { try AliasInput.label("Family 👨‍👩‍👧") }
    }
}
