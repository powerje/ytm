import Testing
import YTMCore
import YTMPlayer

@testable import ytm

@Suite struct ScreenTests {
    func track(_ n: Int, duration: Double = 200) -> Track {
        Track(videoId: "v\(n)", title: "Song \(n)", artists: ["Artist \(n)"], album: "Album \(n)", duration: duration)
    }

    @Test func `every line is exactly the terminal width and there are exactly height lines`() {
        var state = ScreenState()
        state.width = 100
        state.height = 20
        state.results = (1...40).map { .track(track($0)) }
        state.queue.replace(with: (1...30).map { track($0) })
        state.playback.duration = 200
        state.playback.timePos = 50
        for mode in [InputMode.normal, .search] {
            state.mode = mode
            let lines = Screen.render(state)
            #expect(lines.count == 20)
            for line in lines {
                #expect(line.plain.count == 100, "line \(line.id): \(line.plain)")
            }
        }
    }

    @Test func `filter tabs are numbered and the empty pane hints at the library when signed in`() {
        var state = ScreenState()
        state.width = 100
        let anonymous = Screen.render(state)
        #expect(anonymous[0].plain.contains("1 Songs"))
        #expect(anonymous[0].plain.contains("4 Playlists"))
        #expect(anonymous[3].plain.contains("Press / to search."))
        state.loggedIn = true
        #expect(Screen.render(state)[3].plain.contains("1-4 to browse your library"))
    }

    @Test func `tiny terminals do not crash`() {
        var state = ScreenState()
        state.width = 12
        state.height = 4
        state.results = [.track(track(1))]
        state.queue.replace(with: [track(1)])
        let lines = Screen.render(state)
        #expect(lines.count == 4)
        for line in lines { #expect(line.plain.count == 12) }
    }

    @Test func `selected row is inverted and playing row is marked`() {
        var state = ScreenState()
        state.width = 120
        state.height = 24
        state.results = (1...5).map { .track(track($0)) }
        state.resultsCursor.selection = 2
        state.queue.replace(with: (1...3).map { track($0) }, startingAt: 1)
        state.playback.duration = 200
        let lines = Screen.render(state)
        let resultsRows = lines[3...7]
        let selectedRows = resultsRows.filter { $0.segments.contains { $0.style.inverted } }
        #expect(selectedRows.count == 1)
        #expect(selectedRows.first?.plain.contains("Song 3") == true)
        let queueRow = lines[4].plain
        #expect(queueRow.contains("▶"))
        #expect(queueRow.contains("Song 2"))
    }

    @Test func `cursor keeps the selection visible`() {
        var cursor = ListCursor()
        cursor.move(by: 1, count: 0, visibleRows: 5)
        #expect(cursor == ListCursor())
        cursor.move(by: 7, count: 20, visibleRows: 5)
        #expect(cursor.selection == 7)
        #expect(cursor.offset == 3)
        cursor.move(by: -7, count: 20, visibleRows: 5)
        #expect(cursor.selection == 0)
        #expect(cursor.offset == 0)
        cursor.move(by: 100, count: 20, visibleRows: 5)
        #expect(cursor.selection == 19)
        #expect(cursor.offset == 15)
        cursor.clamp(count: 3, visibleRows: 5)
        #expect(cursor.selection == 2)
        #expect(cursor.offset == 0)
    }

    @Test func `text fitting pads and truncates`() {
        #expect(TextFit.pad("abc", to: 5) == "abc  ")
        #expect(TextFit.pad("abcdef", to: 5) == "abcd…")
        #expect(TextFit.truncate("abc", to: 0) == "")
        #expect(TextFit.truncate("abc", to: 1) == "…")
        #expect(TextFit.padLeft("7", to: 3) == "  7")
        let fitted = Screen.fit([Segment("abc"), Segment("defgh", .dim)], to: 6)
        #expect(fitted.map(\.text) == ["abc", "de…"])
        let padded = Screen.fit([Segment("ab")], to: 4)
        #expect(padded.map(\.text).joined() == "ab  ")
    }
}
