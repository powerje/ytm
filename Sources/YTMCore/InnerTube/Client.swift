import Foundation

/// Client for the YouTube Music web API (InnerTube), as used by the website.
public struct InnerTubeClient: Sendable {
    public let transport: any HTTPTransport
    public let credentials: Credentials?

    public init(transport: any HTTPTransport = URLSessionTransport(), credentials: Credentials?) {
        self.transport = transport
        self.credentials = credentials
    }

    public static let origin = "https://music.youtube.com"
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/130.0.0.0 Safari/537.36"

    public var isAuthenticated: Bool { credentials != nil }

    // MARK: - Public API

    public func search(_ query: String, filter: SearchFilter) async throws -> [SearchResult] {
        let root = try await post("search", body: ["query": query, "params": Self.searchParams(for: filter)])
        return Parsers.searchResults(root, filter: filter)
    }

    public func albumTracks(browseId: String) async throws -> TrackList {
        let root = try await post("browse", body: ["browseId": browseId])
        let title = Parsers.pageTitle(root)
        return TrackList(title: title ?? "Album", tracks: Parsers.pageTracks(root, fallbackAlbum: title))
    }

    public func playlistTracks(browseId: String, maxPages: Int = 10) async throws -> TrackList {
        // Playlist ids are browsed with a `VL` prefix; feed ids such as
        // `FEmusic_liked_videos` are used as they are.
        let id = browseId.hasPrefix("VL") || browseId.hasPrefix("FE") ? browseId : "VL" + browseId
        var root = try await post("browse", body: ["browseId": id])
        let title = Parsers.pageTitle(root) ?? "Playlist"
        var tracks = Parsers.pageTracks(root, fallbackAlbum: nil)
        var pages = 1
        while pages < maxPages, let token = Parsers.continuationToken(root) {
            root = try await post("browse", body: ["continuation": token])
            let more = Parsers.pageTracks(root, fallbackAlbum: nil)
            if more.isEmpty { break }
            let known = Set(tracks.map(\.videoId))
            tracks.append(contentsOf: more.filter { !known.contains($0.videoId) })
            pages += 1
        }
        return TrackList(title: title, tracks: tracks)
    }

    /// All songs by an artist when the artist page links to a songs playlist,
    /// otherwise the artist's top songs.
    public func artistTracks(browseId: String) async throws -> TrackList {
        let root = try await post("browse", body: ["browseId": browseId])
        let name = Parsers.pageTitle(root) ?? "Artist"
        if let playlistId = Parsers.artistSongsPlaylistId(root) {
            let list = try await playlistTracks(browseId: playlistId)
            if !list.tracks.isEmpty { return TrackList(title: name, tracks: list.tracks) }
        }
        return TrackList(title: name, tracks: Parsers.pageTracks(root, fallbackAlbum: nil))
    }

    public func likedSongs() async throws -> TrackList {
        try await requireAuth()
        let list = try await playlistTracks(browseId: "FEmusic_liked_videos")
        return TrackList(title: "Liked songs", tracks: list.tracks)
    }

    public func libraryPlaylists() async throws -> [Playlist] {
        try await requireAuth()
        let root = try await post("browse", body: ["browseId": "FEmusic_liked_playlists"])
        return Parsers.libraryPlaylists(root)
    }

    /// Artists in the user's library (subscribed to, or saved from their songs).
    public func libraryArtists() async throws -> [Artist] {
        try await requireAuth()
        return try await browsePages(browseId: "FEmusic_library_corpus_artists", parse: Parsers.libraryArtists)
    }

    /// Albums saved to the user's library.
    public func libraryAlbums() async throws -> [Album] {
        try await requireAuth()
        return try await browsePages(browseId: "FEmusic_liked_albums", parse: Parsers.libraryAlbums)
    }

    /// Browses a feed and follows its continuations, de-duplicating by id.
    private func browsePages<Item: Identifiable>(
        browseId: String, maxPages: Int = 10, parse: (JSON) -> [Item]
    ) async throws -> [Item] {
        var root = try await post("browse", body: ["browseId": browseId])
        var items = parse(root)
        var pages = 1
        while pages < maxPages, let token = Parsers.continuationToken(root) {
            root = try await post("browse", body: ["continuation": token], query: ["ctoken": token, "type": "next"])
            let more = parse(root)
            if more.isEmpty { break }
            let known = Set(items.map(\.id))
            items.append(contentsOf: more.filter { !known.contains($0.id) })
            pages += 1
        }
        return items
    }

    /// Radio (autoplay) tracks seeded by a track. The seed itself is first in
    /// the list and is removed.
    public func radio(for videoId: String) async throws -> [Track] {
        let musicConfig: [String: Any] = [
            "hasPersistentPlaylistPanel": true,
            "musicVideoType": "MUSIC_VIDEO_TYPE_ATV",
        ]
        let body: [String: Any] = [
            "videoId": videoId,
            "playlistId": "RDAMVM" + videoId,
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "params": "wAEB",
            "watchEndpointMusicSupportedConfigs": ["watchEndpointMusicConfig": musicConfig],
        ]
        let root = try await post("next", body: body)
        return Parsers.radioTracks(root).filter { $0.videoId != videoId }
    }

    /// Verifies the stored credentials by requesting the user's library and
    /// checking that YouTube treated the request as signed in.
    public func validateSession() async throws {
        try await requireAuth()
        let root = try await post("browse", body: ["browseId": "FEmusic_liked_playlists"])
        guard Parsers.isSignedIn(root) else { throw YTMError.sessionRejected }
    }

    // MARK: - Request plumbing

    private func requireAuth() async throws {
        guard credentials != nil else { throw YTMError.notLoggedIn }
    }

    static func searchParams(for filter: SearchFilter) -> String {
        let code: String
        switch filter {
        case .songs: code = "II"
        case .artists: code = "Ig"
        case .albums: code = "IY"
        case .playlists: return "Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo%3D"
        }
        return "EgWKAQ" + code + "AWoMEA4QChADEAQQCRAF"
    }

    static func clientVersion(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return "1." + f.string(from: now) + ".01.00"
    }

    func makeRequest(endpoint: String, body: [String: Any], query: [String: String] = [:]) throws -> URLRequest {
        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": Self.clientVersion(),
                "hl": "en",
                "gl": "US",
            ],
            "user": ["lockedSafetyMode": false],
        ]
        var components = URLComponents(string: Self.origin + "/youtubei/v1/" + endpoint)
        components?.queryItems =
            [URLQueryItem(name: "prettyPrint", value: "false")]
            + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else {
            throw YTMError.unexpectedResponse("invalid endpoint \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        request.setValue(Self.origin, forHTTPHeaderField: "X-Origin")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let credentials, let sapisid = credentials.sapisid {
            request.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
            request.setValue(SAPISIDHash.authorization(sapisid: sapisid), forHTTPHeaderField: "Authorization")
            request.setValue(credentials.authUser, forHTTPHeaderField: "X-Goog-AuthUser")
        }
        return request
    }

    func post(_ endpoint: String, body: [String: Any], query: [String: String] = [:]) async throws -> JSON {
        let request = try makeRequest(endpoint: endpoint, body: body, query: query)
        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch let error as YTMError {
            throw error
        } catch {
            throw YTMError.transport(error.localizedDescription)
        }
        if let host = response.url?.host, host != "music.youtube.com" {
            // Redirected away (typically to a sign-in page): the session is gone.
            throw YTMError.sessionExpired
        }
        switch response.statusCode {
        case 200...299: break
        case 401, 403: throw credentials == nil ? YTMError.httpStatus(response.statusCode) : YTMError.sessionExpired
        default: throw YTMError.httpStatus(response.statusCode)
        }
        return try JSON.parse(data)
    }
}
