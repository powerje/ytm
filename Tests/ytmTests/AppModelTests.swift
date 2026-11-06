import Foundation
import Testing
import YTMCore

@testable import YTMPlayer
@testable import ytm

/// Fails every request; nothing here should reach the network.
struct OfflineTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw YTMError.transport("offline")
    }
}

@MainActor
@Suite struct AppModelTests {
    func model() -> AppModel {
        let tools = ExternalTools(mpv: "/usr/bin/true", ytdlp: "/usr/bin/true")
        return AppModel(
            client: InnerTubeClient(transport: OfflineTransport(), credentials: nil),
            player: MpvPlayer(tools: tools), store: ScreenStore())
    }

    let stream = Track(videoId: "live", title: "lofi hip hop radio", artists: ["Lofi Girl"], isLive: true)
    let song = Track(videoId: "s1", title: "Song", artists: ["Artist"], duration: 200)

    @Test func `a dropped live stream is rejoined once, then stopped with a hint`() {
        let m = model()
        m.state.queue.replace(with: [stream])
        m.state.playback.hasFile = true
        m.handle(playerEvent: .ended(reason: "eof"))
        #expect(m.state.playback.loading)
        #expect(m.state.queue.current == stream)
        m.state.playback.hasFile = true
        m.handle(playerEvent: .ended(reason: "eof"))
        #expect(!m.state.playback.loading)
        #expect(m.state.queue.current == stream)
        #expect(m.state.message?.contains("dropped") == true)
    }

    @Test func `starting a stream by hand resets the rejoin limit`() {
        let m = model()
        m.state.queue.replace(with: [stream])
        m.lastLiveReload = Date()
        m.playCurrent()
        #expect(m.lastLiveReload == .distantPast)
    }

    @Test func `radio is never seeded from a live stream`() {
        let m = model()
        m.state.radio = true
        m.state.queue.replace(with: [stream])
        m.handle(playerEvent: .ended(reason: "eof"))
        m.lastLiveReload = Date()
        m.next(auto: true)
        #expect(m.state.busy == nil)
        #expect(m.state.queue.current == stream)
    }

    @Test func `a finished song still advances`() {
        let m = model()
        m.state.queue.replace(with: [song, stream])
        m.handle(playerEvent: .ended(reason: "eof"))
        #expect(m.state.queue.current == stream)
        #expect(m.state.playback.loading)
    }
}
