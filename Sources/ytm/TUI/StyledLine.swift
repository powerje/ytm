import Foundation
import YTMCore

/// How a run of text is drawn. Mapped to terminal attributes by the view layer.
enum Tint: Sendable, Equatable {
    case normal, dim, accent, playing, warning
}

struct Style: Sendable, Equatable {
    var tint: Tint = .normal
    var bold = false
    var inverted = false

    static let normal = Style()
    static let dim = Style(tint: .dim)
    static let accent = Style(tint: .accent)
    static let title = Style(bold: true)
    static let selected = Style(inverted: true)
    static let playing = Style(tint: .playing, bold: true)
    static let selectedPlaying = Style(tint: .playing, bold: true, inverted: true)
    static let warning = Style(tint: .warning, bold: true)
}

struct Segment: Sendable, Equatable {
    var text: String
    var style: Style

    /// `text` is made terminal-safe: control characters and bidirectional
    /// overrides are dropped, so a title cannot move the cursor or restyle
    /// the screen.
    init(_ text: String, _ style: Style = .normal) {
        self.text = terminalSafe(text)
        self.style = style
    }
}

/// One terminal row, exactly `width` characters when produced by `Screen`.
struct StyledLine: Sendable, Equatable, Identifiable {
    let id: Int
    var segments: [Segment]

    var plain: String { segments.map(\.text).joined() }
}

/// Fits text to a number of terminal columns. Widths are display widths:
/// emoji and East Asian wide characters take two columns, so a row that
/// contains them has fewer characters than columns.
enum TextFit {
    /// Truncates to `width` columns, ending with an ellipsis when cut.
    static func truncate(_ text: String, to width: Int) -> String {
        guard width > 0 else { return "" }
        guard displayWidth(text) > width else { return text }
        guard width > 1 else { return "…" }
        var kept = ""
        var used = 0
        for character in text {
            let w = displayWidth(character)
            guard used + w <= width - 1 else { break }
            kept.append(character)
            used += w
        }
        return kept + "…"
    }

    /// Pads with spaces on the right, or truncates, to exactly `width` columns.
    static func pad(_ text: String, to width: Int) -> String {
        let cut = truncate(text, to: width)
        return cut + String(repeating: " ", count: max(0, width - displayWidth(cut)))
    }

    /// Pads with spaces on the left, or truncates, to exactly `width` columns.
    static func padLeft(_ text: String, to width: Int) -> String {
        let cut = truncate(text, to: width)
        return String(repeating: " ", count: max(0, width - displayWidth(cut))) + cut
    }

    static func displayWidth(_ text: String) -> Int {
        text.reduce(0) { $0 + displayWidth($1) }
    }

    /// Columns a character occupies: two for emoji shown as pictures and
    /// for East Asian wide and fullwidth characters, otherwise one.
    static func displayWidth(_ character: Character) -> Int {
        let scalars = character.unicodeScalars
        let emojiStyle = scalars.contains { $0.value == 0xFE0F }
        for scalar in scalars {
            let properties = scalar.properties
            if properties.isEmojiPresentation || (emojiStyle && properties.isEmoji) || isEastAsianWide(scalar) {
                return 2
            }
        }
        return 1
    }

    private static func isEastAsianWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
            0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
            0xFFE0...0xFFE6, 0x20000...0x2FFFD, 0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}
