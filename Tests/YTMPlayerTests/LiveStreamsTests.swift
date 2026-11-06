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

    @Test func `a channel without favorites keeps the listing order`() {
        let channel = LiveChannel(name: "x", streamsURL: "https://example.invalid", favorites: [])
        #expect(
            LiveStreams.parse(output, channel: channel).map(\.videoId) == ["xmas", "asian", "sleep", "main", "wave"])
    }
}
