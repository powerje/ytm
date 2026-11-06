import Foundation

/// Strips characters that a terminal would interpret rather than display:
/// control characters (including escape sequences) and bidirectional
/// overrides. Titles come from YouTube and are shown verbatim otherwise.
public func terminalSafe(_ text: String) -> String {
    let scalars = text.unicodeScalars.filter { scalar in
        switch scalar.properties.generalCategory {
        case .control: return false
        default: break
        }
        switch scalar.value {
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return false
        default: return true
        }
    }
    return String(String.UnicodeScalarView(scalars))
}
