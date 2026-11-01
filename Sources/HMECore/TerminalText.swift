import Foundation

/// Keeps text from Apple's responses from driving the terminal it is printed to.
public enum TerminalText {
    private static let bidiControls: Set<UInt32> = [
        0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
    ]

    /// Control characters (C0, DEL, C1) and bidirectional overrides; emoji joiners stay allowed.
    public static func isUnsafe(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control: true
        case .format: bidiControls.contains(scalar.value)
        default: false
        }
    }

    public static func clean(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { isUnsafe($0) ? "?" : $0 }))
    }

    /// Escapes the unsafe characters JSONEncoder leaves as they are (DEL, C1, bidi overrides);
    /// the newlines of pretty-printed output are layout and stay.
    public static func escapingJSON(_ json: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in json.unicodeScalars {
            if scalar != "\n" && isUnsafe(scalar) {
                for unit in String(scalar).utf16 {
                    result.append(contentsOf: String(format: "\\u%04x", unit).unicodeScalars)
                }
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }
}
