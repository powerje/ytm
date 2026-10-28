import Foundation
import YTMCore

/// An ordered play queue with a current position.
public struct Queue: Sendable, Equatable {
    public private(set) var tracks: [Track] = []
    public private(set) var index: Int?

    public init() {}

    public var current: Track? {
        guard let index, tracks.indices.contains(index) else { return nil }
        return tracks[index]
    }

    public var isEmpty: Bool { tracks.isEmpty }
    public var count: Int { tracks.count }
    public var hasNext: Bool { index.map { $0 + 1 < tracks.count } ?? !tracks.isEmpty }
    public var hasPrevious: Bool { index.map { $0 > 0 } ?? false }

    /// Replaces the queue and positions at `startingAt`.
    public mutating func replace(with newTracks: [Track], startingAt start: Int = 0) {
        tracks = newTracks
        index = newTracks.isEmpty ? nil : min(max(start, 0), newTracks.count - 1)
    }

    public mutating func append(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
    }

    public mutating func append(_ track: Track) {
        tracks.append(track)
    }

    /// Inserts right after the current track.
    public mutating func playNext(_ track: Track) {
        let position = index.map { $0 + 1 } ?? 0
        tracks.insert(track, at: min(position, tracks.count))
    }

    public mutating func clear() {
        tracks = []
        index = nil
    }

    @discardableResult
    public mutating func advance() -> Track? {
        guard hasNext else { return nil }
        index = (index ?? -1) + 1
        return current
    }

    @discardableResult
    public mutating func goBack() -> Track? {
        guard hasPrevious, let index else { return nil }
        self.index = index - 1
        return current
    }

    @discardableResult
    public mutating func jump(to position: Int) -> Track? {
        guard tracks.indices.contains(position) else { return nil }
        index = position
        return current
    }

    public mutating func remove(at position: Int) {
        guard tracks.indices.contains(position) else { return }
        tracks.remove(at: position)
        guard let index else { return }
        if tracks.isEmpty {
            self.index = nil
        } else if position < index {
            self.index = index - 1
        } else if position == index, index >= tracks.count {
            self.index = tracks.count - 1
        }
    }
}
