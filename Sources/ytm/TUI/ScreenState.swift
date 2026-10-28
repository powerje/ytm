import Foundation
import YTMCore
import YTMPlayer

enum Pane: Sendable, Equatable {
    case results, queue
}

enum InputMode: Sendable, Equatable {
    case normal, search
}

/// Selection plus scroll offset for a list pane.
struct ListCursor: Sendable, Equatable {
    var selection = 0
    var offset = 0

    mutating func move(by delta: Int, count: Int, visibleRows: Int) {
        guard count > 0 else {
            selection = 0
            offset = 0
            return
        }
        selection = min(max(selection + delta, 0), count - 1)
        clamp(count: count, visibleRows: visibleRows)
    }

    mutating func jump(to index: Int, count: Int, visibleRows: Int) {
        selection = index
        move(by: 0, count: count, visibleRows: visibleRows)
    }

    mutating func clamp(count: Int, visibleRows: Int) {
        guard count > 0 else {
            selection = 0
            offset = 0
            return
        }
        selection = min(max(selection, 0), count - 1)
        let rows = max(visibleRows, 1)
        if selection < offset { offset = selection }
        if selection >= offset + rows { offset = selection - rows + 1 }
        offset = min(max(offset, 0), max(count - rows, 0))
    }
}

/// Everything the screen renderer needs. A value type so rendering is a
/// pure function and can be tested without a terminal.
struct ScreenState: Sendable, Equatable {
    var width = 80
    var height = 24

    var mode: InputMode = .normal
    var pane: Pane = .results
    var query = ""
    var filter: SearchFilter = .songs

    var resultsTitle = "Results"
    var results: [SearchResult] = []
    var resultsCursor = ListCursor()
    var hasLoadedResults = false

    var queue = Queue()
    var queueCursor = ListCursor()

    var playback = PlaybackState()
    var radio = true
    var loggedIn = false

    var busy: String?
    var message: String?

    /// Rows available to each list pane below its header line.
    var listRows: Int { max(height - 6, 1) }
    var resultsPaneWidth: Int { max(width * 55 / 100, 10) }
    var queuePaneWidth: Int { max(width - resultsPaneWidth - 1, 10) }
}

enum Screen {
    static func render(_ s: ScreenState) -> [StyledLine] {
        var lines: [[Segment]] = []
        lines.append(searchBar(s))
        lines.append([Segment(String(repeating: "─", count: s.width), .dim)])
        let body = bodyLines(s)
        lines.append(contentsOf: body)
        lines.append([Segment(String(repeating: "─", count: s.width), .dim)])
        lines.append(nowPlaying(s))
        lines.append(statusLine(s))
        if lines.count > s.height {
            lines = Array(lines.prefix(s.height))
        }
        return lines.enumerated().map { StyledLine(id: $0.offset, segments: $0.element) }
    }

    // MARK: - Rows

    private static func searchBar(_ s: ScreenState) -> [Segment] {
        var tabs: [Segment] = []
        for (index, filter) in SearchFilter.allCases.enumerated() {
            let label = " \(index + 1) \(filter.title) "
            tabs.append(Segment(label, filter == s.filter ? .selected : .dim))
        }
        let tabsWidth = tabs.reduce(0) { $0 + $1.text.count }
        let inputWidth = max(s.width - tabsWidth - 1, 0)
        let prompt = s.mode == .search ? "/ " : "/ "
        let cursor = s.mode == .search ? "▏" : ""
        var text = prompt + s.query + cursor
        if s.mode == .normal, s.query.isEmpty {
            text = "/ type to search"
        }
        let inputStyle: Style = s.mode == .search ? .normal : (s.query.isEmpty ? .dim : .normal)
        var segments = [Segment(TextFit.pad(text, to: inputWidth), inputStyle), Segment(" ")]
        segments.append(contentsOf: tabs)
        return fit(segments, to: s.width)
    }

    private static func bodyLines(_ s: ScreenState) -> [[Segment]] {
        let left = resultsPane(s)
        let right = queuePane(s)
        var rows: [[Segment]] = []
        for i in 0..<(s.listRows + 1) {
            var row = i < left.count ? left[i] : [Segment(String(repeating: " ", count: s.resultsPaneWidth))]
            row.append(Segment("│", .dim))
            row.append(contentsOf: i < right.count ? right[i] : [])
            rows.append(fit(row, to: s.width))
        }
        return rows
    }

    private static func resultsPane(_ s: ScreenState) -> [[Segment]] {
        let width = s.resultsPaneWidth
        var rows: [[Segment]] = []
        var header = s.resultsTitle
        if !s.results.isEmpty { header += " (\(s.results.count))" }
        if let busy = s.busy { header = busy }
        rows.append([Segment(TextFit.pad(" " + header, to: width), s.pane == .results ? .title : .dim)])
        if s.results.isEmpty, s.busy == nil {
            let hint =
                s.hasLoadedResults
                ? " No results."
                : (s.loggedIn ? " Press / to search, or 1-4 to browse your library." : " Press / to search.")
            rows.append([Segment(TextFit.pad(hint, to: width), .dim)])
            return rows
        }
        let focused = s.pane == .results
        for row in 0..<s.listRows {
            let index = s.resultsCursor.offset + row
            guard index < s.results.count else { break }
            let selected = focused && index == s.resultsCursor.selection
            let text = describe(s.results[index], width: width)
            rows.append([Segment(TextFit.pad(text, to: width), selected ? .selected : .normal)])
        }
        return rows
    }

    private static func queuePane(_ s: ScreenState) -> [[Segment]] {
        let width = s.queuePaneWidth
        var rows: [[Segment]] = []
        var header = " Queue"
        if !s.queue.isEmpty {
            header += " (\(s.queue.count))"
            let total = s.queue.tracks.compactMap(\.duration).reduce(0, +)
            if total > 0 { header += " · \(formatDuration(total))" }
        }
        rows.append([Segment(TextFit.pad(header, to: width), s.pane == .queue ? .title : .dim)])
        if s.queue.isEmpty {
            rows.append([Segment(TextFit.pad(" Empty. Enter plays, a adds to the queue.", to: width), .dim)])
            return rows
        }
        let focused = s.pane == .queue
        for row in 0..<s.listRows {
            let index = s.queueCursor.offset + row
            guard index < s.queue.count else { break }
            let track = s.queue.tracks[index]
            let selected = focused && index == s.queueCursor.selection
            let playing = index == s.queue.index
            let marker = playing ? (s.playback.paused ? "‖ " : "▶ ") : "  "
            let number = TextFit.padLeft("\(index + 1)", to: 3) + " "
            let duration = formatDuration(track.duration)
            let bodyWidth = max(width - marker.count - number.count - duration.count - 1, 4)
            let body = TextFit.pad(trackLabel(track), to: bodyWidth)
            let text = marker + number + body + " " + duration
            let style: Style = selected ? (playing ? .selectedPlaying : .selected) : (playing ? .playing : .normal)
            rows.append([Segment(TextFit.pad(text, to: width), style)])
        }
        return rows
    }

    private static func nowPlaying(_ s: ScreenState) -> [Segment] {
        guard let track = s.queue.current, s.playback.duration != nil || s.playback.loading else {
            return fit([Segment(" Nothing playing.", .dim)], to: s.width)
        }
        let marker = s.playback.loading ? " … " : (s.playback.paused ? " ‖ " : " ▶ ")
        var segments = [Segment(marker, .playing), Segment(track.title, .title)]
        if !track.artists.isEmpty { segments.append(Segment("  " + track.artistLine)) }
        if let album = track.album { segments.append(Segment("  [\(album)]", .dim)) }
        return fit(segments, to: s.width)
    }

    private static func statusLine(_ s: ScreenState) -> [Segment] {
        var segments: [Segment] = []
        let position = formatDuration(s.playback.timePos ?? (s.playback.duration == nil ? nil : 0))
        let duration = formatDuration(s.playback.duration)
        segments.append(Segment(" \(position)/\(duration) "))
        let barWidth = min(max(s.width / 4, 8), 30)
        var filled = 0
        if let t = s.playback.timePos, let d = s.playback.duration, d > 0 {
            filled = Int((t / d * Double(barWidth)).rounded(.down))
            filled = min(max(filled, 0), barWidth)
        }
        segments.append(Segment(String(repeating: "━", count: filled), .accent))
        segments.append(Segment(String(repeating: "─", count: barWidth - filled), .dim))
        segments.append(Segment("  vol \(Int(s.playback.volume))"))
        segments.append(Segment("  radio \(s.radio ? "on" : "off")", s.radio ? .accent : .dim))
        if let message = s.message {
            segments.append(Segment("  " + message, .warning))
        } else {
            let hints: String
            switch s.mode {
            case .search: hints = "  Enter search · Esc cancel"
            case .normal:
                hints =
                    "  / search · 1-4 filter · Enter play · a add · o open · Tab pane · Space pause · n/p"
                    + " · ,/. seek · -/+ vol · r radio · q quit"
            }
            segments.append(Segment(hints, .dim))
        }
        return fit(segments, to: s.width)
    }

    // MARK: - Helpers

    static func trackLabel(_ track: Track) -> String {
        track.artists.isEmpty ? track.title : "\(track.title) — \(track.artistLine)"
    }

    static func describe(_ result: SearchResult, width: Int) -> String {
        switch result {
        case .track(let t):
            let duration = formatDuration(t.duration)
            var label = trackLabel(t)
            if let album = t.album, !album.isEmpty, album != t.title { label += "  [\(album)]" }
            let bodyWidth = max(width - duration.count - 3, 4)
            return " " + TextFit.pad(label, to: bodyWidth) + " " + duration
        case .artist(let a):
            return " artist   \(a.name)" + (a.subtitle.map { "  · \($0)" } ?? "")
        case .album(let a):
            var label = " album    \(a.title)"
            if !a.artists.isEmpty { label += " — " + a.artists.joined(separator: ", ") }
            if let year = a.year { label += "  (\(year))" }
            return label
        case .playlist(let p):
            return " playlist \(p.title)" + (p.subtitle.map { "  · \($0)" } ?? "")
        }
    }

    /// Truncates or pads a row of segments to exactly `width` characters.
    static func fit(_ segments: [Segment], to width: Int) -> [Segment] {
        var out: [Segment] = []
        var used = 0
        for segment in segments {
            guard used < width else { break }
            let remaining = width - used
            if segment.text.count <= remaining {
                out.append(segment)
                used += segment.text.count
            } else {
                out.append(Segment(TextFit.truncate(segment.text, to: remaining), segment.style))
                used = width
            }
        }
        if used < width {
            out.append(Segment(String(repeating: " ", count: width - used)))
        }
        return out
    }
}
