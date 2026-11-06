import Foundation
import Testing
import YTMCore

@testable import YTMPlayer

@Suite struct LiveStreamsTests {
    let output = """
        {"id": "xmas", "title": "christmas lofi radio 🎄 cozy ambience to relax to", "live_status": "is_live"}
        {"id": "asian", "title": "asian lofi radio ⛩️ beats to relax/study to", "live_status": "is_live"}
        {"id": "sleep", "title": "sleep lofi radio 🌌 relaxing music to sleep/dream to", "live_status": "is_live"}
        not json at all
        {"id": "main", "title": "lofi hip hop radio 📚 beats to relax/study to ", "live_status": "is_live"}
        {"id": "old", "title": "lofi hip hop radio - beats to relax/study to", "live_status": "was_live"}
        {"id": "wave", "title": "synthwave radio 🌌 beats to chill/game to", "live_status": "is_live"}
        {"title": "no id", "live_status": "is_live"}

        """

    @Test func `favorites come first in their own order, then the rest in channel order`() {
        let tracks = LiveStreams.parse(output, channel: .lofiGirl)
        #expect(tracks.map(\.videoId) == ["main", "sleep", "wave", "xmas", "asian"])
    }

    @Test func `streams are live tracks credited to the channel`() {
        let tracks = LiveStreams.parse(output, channel: .lofiGirl)
        #expect(tracks.allSatisfy { $0.isLive })
        #expect(tracks.allSatisfy { $0.artists == ["Lofi Girl"] && $0.duration == nil })
        #expect(tracks.first?.title == "lofi hip hop radio 📚 beats to relax/study to")
    }

    @Test func `a stream matching two favorite patterns is listed once`() {
        let channel = LiveChannel(name: "x", streamsURL: "u", favorites: [["sleep"], ["lofi radio"], ["synthwave"]])
        #expect(
            LiveStreams.parse(output, channel: channel).map(\.videoId) == ["sleep", "xmas", "wave", "asian", "main"])
    }

    @Test func `favorite matching ignores case and takes the first of several matches`() {
        let channel = LiveChannel(name: "x", streamsURL: "u", favorites: [["RELAX/STUDY"]])
        #expect(LiveStreams.parse(output, channel: channel).first?.videoId == "asian")
    }

    @Test func `a channel without favorites keeps the listing order`() {
        let channel = LiveChannel(name: "x", streamsURL: "https://example.invalid", favorites: [])
        #expect(
            LiveStreams.parse(output, channel: channel).map(\.videoId) == ["xmas", "asian", "sleep", "main", "wave"])
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
            echo '{"id": "a", "title": "radio", "live_status": "is_live"}'
            echo 'ERROR: one entry failed' >&2
            exit 1
            """)
        let tracks = try await LiveStreams.list(.lofiGirl, tools: tools)
        #expect(tracks.map(\.videoId) == ["a"])
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
