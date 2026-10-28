import Foundation

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

    init(_ text: String, _ style: Style = .normal) {
        self.text = text
        self.style = style
    }
}

/// One terminal row, exactly `width` characters when produced by `Screen`.
struct StyledLine: Sendable, Equatable, Identifiable {
    let id: Int
    var segments: [Segment]

    var plain: String { segments.map(\.text).joined() }
}

enum TextFit {
    /// Truncates to `width` characters, ending with an ellipsis when cut.
    static func truncate(_ text: String, to width: Int) -> String {
        guard width > 0 else { return "" }
        guard text.count > width else { return text }
        guard width > 1 else { return "…" }
        return String(text.prefix(width - 1)) + "…"
    }

    /// Pads with spaces on the right, or truncates, to exactly `width`.
    static func pad(_ text: String, to width: Int) -> String {
        let cut = truncate(text, to: width)
        return cut + String(repeating: " ", count: max(0, width - cut.count))
    }

    /// Pads with spaces on the left, or truncates, to exactly `width`.
    static func padLeft(_ text: String, to width: Int) -> String {
        let cut = truncate(text, to: width)
        return String(repeating: " ", count: max(0, width - cut.count)) + cut
    }
}
