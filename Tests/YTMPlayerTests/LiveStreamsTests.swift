import Foundation
import Testing
import YTMCore

@testable import YTMPlayer

@Suite struct LiveStreamsTests {
    let output = """
        {"id": "xmas_______", "title": "christmas lofi radio 🎄 cozy ambience to relax to", "live_status": "is_live"}
        {"id": "asian______", "title": "asian lofi radio ⛩️ beats to relax/study to", "live_status": "is_live"}
        {"id": "sleep______", "title": "sleep lofi radio 🌌 relaxing music to sleep/dream to", "live_status": "is_live"}
        not json at all
        {"id": "main_______", "title": "lofi hip hop radio 📚 beats to relax/study to ", "live_status": "is_live"}
        {"id": "old________", "title": "lofi hip hop radio - beats to relax/study to", "live_status": "was_live"}
        {"id": "wave_______", "title": "synthwave radio 🌌 beats to chill/game to", "live_status": "is_live"}
        {"title": "no id", "live_status": "is_live"}

        """

    @Test func `favorites come first in their own order, then the rest in channel order`() {
        let tracks = LiveStreams.parse(output, channel: .lofiGirl).tracks
        #expect(tracks.map(\.videoId) == ["main_______", "sleep______", "wave_______", "xmas_______", "asian______"])
        #expect(LiveChannel.lofiGirl.isPrimary(tracks[0]))
        #expect(!LiveChannel.lofiGirl.isPrimary(tracks[1]))
    }

    @Test func `streams are live tracks credited to the channel`() {
        let tracks = LiveStreams.parse(output, channel: .lofiGirl).tracks
        #expect(tracks.allSatisfy { $0.isLive })
        #expect(tracks.allSatisfy { $0.artists == ["Lofi Girl"] && $0.duration == nil })
        #expect(tracks.first?.title == "lofi hip hop radio 📚 beats to relax/study to")
    }

    @Test func `a stream matching two favorite patterns is listed once`() {
        let channel = LiveChannel(name: "x", streamsURL: "u", favorites: [["sleep"], ["lofi radio"], ["synthwave"]])
        #expect(
            LiveStreams.parse(output, channel: channel).tracks.map(\.videoId) == [
                "sleep______", "xmas_______", "wave_______", "asian______", "main_______",
            ])
    }

    @Test func `favorite matching ignores case and takes the first of several matches`() {
        let channel = LiveChannel(name: "x", streamsURL: "u", favorites: [["RELAX/STUDY"]])
        #expect(LiveStreams.parse(output, channel: channel).tracks.first?.videoId == "asian______")
    }

    @Test func `a channel without favorites keeps the listing order`() {
        let channel = LiveChannel(name: "x", streamsURL: "https://example.invalid", favorites: [])
        #expect(
            LiveStreams.parse(output, channel: channel).tracks.map(\.videoId) == [
                "xmas_______", "asian______", "sleep______", "main_______", "wave_______",
            ])
    }

    @Test func `ids that are not video ids and control characters in titles are dropped`() {
        let output = """
            {"id": "../etc", "title": "bad id", "live_status": "is_live"}
            {"id": "a&b=c#d e f", "title": "bad id", "live_status": "is_live"}
            {"id": "rFZHOHl-L8A", "title": "radio \\u001b[2J \\u202eevil\\t ok", "live_status": "is_live"}
            """
        let tracks = LiveStreams.parse(output, channel: .lofiGirl).tracks
        #expect(tracks.map(\.videoId) == ["rFZHOHl-L8A"])
        #expect(tracks.first?.title == "radio [2J evil ok")
    }

    @Test func `entries without a live status are counted so an old yt-dlp can be reported`() {
        let parsed = LiveStreams.parse(#"{"id": "rFZHOHl-L8A", "title": "radio"}"#, channel: .lofiGirl)
        #expect(parsed.tracks.isEmpty)
        #expect(parsed.entriesWithoutStatus == 1)
    }

    /// Writes a shell script that stands in for yt-dlp.
    func fakeYtdlp(_ body: String) throws -> ExternalTools {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("fake-yt-dlp-\(UUID().uuidString)")
            .path
        try ("#!/bin/sh\n" + body + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return ExternalTools(mpv: path, ytdlp: path)
    }

    @Test func `a non-zero exit with output still returns the streams`() async throws {
        let tools = try fakeYtdlp(
            """
            echo '{"id": "aaaaaaaaaaa", "title": "radio", "live_status": "is_live"}'
            echo 'ERROR: one entry failed' >&2
            exit 1
            """)
        let tracks = try await LiveStreams.list(.lofiGirl, tools: tools)
        #expect(tracks.map(\.videoId) == ["aaaaaaaaaaa"])
    }

    @Test func `an old yt-dlp that reports no live status is called out`() async throws {
        let tools = try fakeYtdlp(#"echo '{"id": "rFZHOHl-L8A", "title": "radio"}'"#)
        do {
            _ = try await LiveStreams.list(.lofiGirl, tools: tools)
            Issue.record("expected an error")
        } catch {
            #expect("\(error)".contains("too old"))
        }
    }

    @Test func `a timeout is an error even when part of the list arrived`() async throws {
        let tools = try fakeYtdlp(
            """
            echo '{"id": "rFZHOHl-L8A", "title": "radio", "live_status": "is_live"}'
            sleep 5
            """)
        do {
            _ = try await LiveStreams.list(.lofiGirl, tools: tools, timeout: 0.3)
            Issue.record("expected an error")
        } catch {
            #expect("\(error)".contains("did not answer"))
        }
    }

    @Test func `a failure with no output surfaces the last line of stderr`() async throws {
        let tools = try fakeYtdlp(
            """
            echo 'WARNING: first' >&2
            echo 'ERROR: [youtube] channel page changed' >&2
            exit 1
            """)
        do {
            _ = try await LiveStreams.list(.lofiGirl, tools: tools)
            Issue.record("expected an error")
        } catch {
            #expect("\(error)" == "ERROR: [youtube] channel page changed")
        }
    }
}
