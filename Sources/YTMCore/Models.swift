import Foundation

public struct Track: Identifiable, Hashable, Sendable {
    public let videoId: String
    public let title: String
    public let artists: [String]
    public let album: String?
    public let duration: TimeInterval?

    public init(videoId: String, title: String, artists: [String], album: String? = nil, duration: TimeInterval? = nil)
    {
        self.videoId = videoId
        self.title = title
        self.artists = artists
        self.album = album
        self.duration = duration
    }

    public var id: String { videoId }
    public var artistLine: String { artists.joined(separator: ", ") }
    public var watchURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "music.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoId)]
        // swiftlint:disable:next force_unwrapping
        return components.url!
    }
}

public struct Artist: Identifiable, Hashable, Sendable {
    public let browseId: String
    public let name: String
    public let subtitle: String?

    public init(browseId: String, name: String, subtitle: String? = nil) {
        self.browseId = browseId
        self.name = name
        self.subtitle = subtitle
    }

    public var id: String { browseId }
}

public struct Album: Identifiable, Hashable, Sendable {
    public let browseId: String
    public let title: String
    public let artists: [String]
    public let year: String?

    public init(browseId: String, title: String, artists: [String], year: String? = nil) {
        self.browseId = browseId
        self.title = title
        self.artists = artists
        self.year = year
    }

    public var id: String { browseId }
}

public struct Playlist: Identifiable, Hashable, Sendable {
    /// Browse id, including the `VL` prefix when present.
    public let browseId: String
    public let title: String
    public let subtitle: String?

    public init(browseId: String, title: String, subtitle: String? = nil) {
        self.browseId = browseId
        self.title = title
        self.subtitle = subtitle
    }

    public var id: String { browseId }
}

public enum SearchFilter: String, CaseIterable, Sendable {
    case songs, artists, albums, playlists

    public var title: String { rawValue.capitalized }
}

public enum SearchResult: Identifiable, Hashable, Sendable {
    case track(Track)
    case artist(Artist)
    case album(Album)
    case playlist(Playlist)

    public var id: String {
        switch self {
        case .track(let t): return "t:" + t.id
        case .artist(let a): return "a:" + a.id
        case .album(let a): return "al:" + a.id
        case .playlist(let p): return "p:" + p.id
        }
    }
}

/// Tracks for an artist, album or playlist page, plus the page title.
public struct TrackList: Sendable {
    public let title: String
    public let tracks: [Track]

    public init(title: String, tracks: [Track]) {
        self.title = title
        self.tracks = tracks
    }
}

public func formatDuration(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
