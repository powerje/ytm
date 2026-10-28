import Foundation

/// A decoded terminal key press, delivered to `Application.keyHandler`.
public enum KeyEvent: Equatable {
    case character(Character)
    case up, down, left, right
    case enter, escape, backspace, tab
    case pageUp, pageDown, home, end
}

/// Decodes a chunk of raw terminal input into key events. A lone escape byte
/// at the end of a chunk is reported as `.escape`; escape sequences for
/// arrows, paging and home/end are recognized, anything else after an escape
/// is reported as `.escape` followed by the remaining characters.
struct KeyEventParser {
    func parse(_ string: String) -> [KeyEvent] {
        var events: [KeyEvent] = []
        let chars = Array(string)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\u{1b}" {
                if i + 2 < chars.count, chars[i + 1] == "[" || chars[i + 1] == "O" {
                    let final = chars[i + 2]
                    switch final {
                    case "A": events.append(.up); i += 3; continue
                    case "B": events.append(.down); i += 3; continue
                    case "C": events.append(.right); i += 3; continue
                    case "D": events.append(.left); i += 3; continue
                    case "H": events.append(.home); i += 3; continue
                    case "F": events.append(.end); i += 3; continue
                    case "5", "6", "1", "4", "7", "8":
                        if i + 3 < chars.count, chars[i + 3] == "~" {
                            switch final {
                            case "5": events.append(.pageUp)
                            case "6": events.append(.pageDown)
                            case "1", "7": events.append(.home)
                            default: events.append(.end)
                            }
                            i += 4
                            continue
                        }
                    default: break
                    }
                }
                events.append(.escape)
                i += 1
                continue
            }
            switch c {
            case "\r", "\n": events.append(.enter)
            case "\u{7f}", "\u{08}": events.append(.backspace)
            case "\t": events.append(.tab)
            default: events.append(.character(c))
            }
            i += 1
        }
        return events
    }
}
