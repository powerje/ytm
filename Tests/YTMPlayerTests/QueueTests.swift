import Testing
import YTMCore

@testable import YTMPlayer

@Suite struct QueueTests {
    func track(_ n: Int) -> Track { Track(videoId: "v\(n)", title: "t\(n)", artists: []) }

    @Test func `replace then advance, go back and jump`() {
        var q = Queue()
        #expect(q.current == nil)
        #expect(q.advance() == nil)
        q.replace(with: [track(1), track(2), track(3)])
        #expect(q.current == track(1))
        #expect(q.advance() == track(2))
        #expect(q.advance() == track(3))
        #expect(q.advance() == nil)
        #expect(q.current == track(3))
        #expect(q.goBack() == track(2))
        #expect(q.jump(to: 0) == track(1))
        #expect(q.goBack() == nil)
        #expect(q.jump(to: 9) == nil)
    }

    @Test func `append and play next`() {
        var q = Queue()
        q.append(track(1))
        #expect(q.current == nil)
        #expect(q.advance() == track(1))
        q.append([track(2), track(3)])
        q.playNext(track(9))
        #expect(q.tracks.map(\.videoId) == ["v1", "v9", "v2", "v3"])
        #expect(q.advance() == track(9))
    }

    @Test func `remove adjusts the current index`() {
        var q = Queue()
        q.replace(with: [track(1), track(2), track(3)], startingAt: 2)
        q.remove(at: 0)
        #expect(q.current == track(3))
        q.remove(at: 1)
        #expect(q.current == track(2))
        q.remove(at: 0)
        #expect(q.current == nil)
        #expect(q.isEmpty)
    }
}
