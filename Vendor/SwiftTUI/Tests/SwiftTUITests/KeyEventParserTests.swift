import XCTest
@testable import SwiftTUI

final class KeyEventParserTests: XCTestCase {
    let parser = KeyEventParser()

    func testPlainCharacters() {
        XCTAssertEqual(parser.parse("ab"), [.character("a"), .character("b")])
    }

    func testControlKeys() {
        XCTAssertEqual(parser.parse("\r"), [.enter])
        XCTAssertEqual(parser.parse("\n"), [.enter])
        XCTAssertEqual(parser.parse("\u{7f}"), [.backspace])
        XCTAssertEqual(parser.parse("\t"), [.tab])
    }

    func testArrowsAndNavigation() {
        XCTAssertEqual(parser.parse("\u{1b}[A\u{1b}[B\u{1b}[C\u{1b}[D"), [.up, .down, .right, .left])
        XCTAssertEqual(parser.parse("\u{1b}OA"), [.up])
        XCTAssertEqual(parser.parse("\u{1b}[5~\u{1b}[6~"), [.pageUp, .pageDown])
        XCTAssertEqual(parser.parse("\u{1b}[H\u{1b}[F"), [.home, .end])
        XCTAssertEqual(parser.parse("\u{1b}[1~\u{1b}[4~"), [.home, .end])
    }

    func testLoneEscape() {
        XCTAssertEqual(parser.parse("\u{1b}"), [.escape])
        XCTAssertEqual(parser.parse("\u{1b}x"), [.escape, .character("x")])
    }
}
