import Foundation
import Testing

@testable import YTMCore

@Suite struct ClientTests {
    @Test func `search for songs parses tracks and sends the songs filter`() async throws {
        let transport = FixtureTransport()
        try transport.serve("search", fixture: "search_songs")
        let client = InnerTubeClient(transport: transport, credentials: nil)
        let results = try await client.search("daft punk", filter: .songs)
        #expect(results.count >= 15)
        guard case .track(let first) = try #require(results.first) else { Issue.record("expected track"); return }
        #expect(first.videoId == "NOMa56y_Was")
        #expect(first.title.hasPrefix("End of Line"))
        #expect(first.artists == ["Daft Punk"])
        #expect(first.album != nil)
        #expect(first.duration != nil)
        let body = try transport.lastBody()
        #expect(body["query"] as? String == "daft punk")
        #expect(body["params"] as? String == "EgWKAQIIAWoMEA4QChADEAQQCRAF")
        let context = try #require(body["context"] as? [String: Any])
        let clientInfo = try #require(context["client"] as? [String: Any])
        #expect(clientInfo["clientName"] as? String == "WEB_REMIX")
    }

    @Test func `search for artists`() async throws {
        let transport = FixtureTransport()
        try transport.serve("search", fixture: "search_artists")
        let results = try await InnerTubeClient(transport: transport, credentials: nil).search(
            "daft punk", filter: .artists)
        guard case .artist(let a) = try #require(results.first) else { Issue.record("expected artist"); return }
        #expect(a.name == "Daft Punk")
        #expect(a.browseId == "UCRr1xG_2WIDs18a6cIiCxeA")
    }

    @Test func `search for albums`() async throws {
        let transport = FixtureTransport()
        try transport.serve("search", fixture: "search_albums")
        let results = try await InnerTubeClient(transport: transport, credentials: nil).search(
            "daft punk", filter: .albums)
        guard case .album(let a) = try #require(results.first) else { Issue.record("expected album"); return }
        #expect(a.title == "Random Access Memories")
        #expect(a.browseId == "MPREb_K8qWMWVqXGi")
        #expect(a.artists == ["Daft Punk"])
        #expect(a.year == "2013")
    }

    @Test func `search for playlists`() async throws {
        let transport = FixtureTransport()
        try transport.serve("search", fixture: "search_playlists")
        let results = try await InnerTubeClient(transport: transport, credentials: nil).search(
            "daft punk", filter: .playlists)
        guard case .playlist(let p) = try #require(results.first) else { Issue.record("expected playlist"); return }
        #expect(p.browseId.hasPrefix("VL"))
        #expect(!p.title.isEmpty)
    }

    @Test func `album page uses the header title as the album name`() async throws {
        let transport = FixtureTransport()
        try transport.serve("browse", fixture: "browse_album")
        let list = try await InnerTubeClient(transport: transport, credentials: nil).albumTracks(
            browseId: "MPREb_K8qWMWVqXGi")
        #expect(list.title == "Random Access Memories")
        #expect(list.tracks.count == 13)
        let first = try #require(list.tracks.first)
        #expect(first.title == "Give Life Back to Music")
        #expect(first.artists == ["Daft Punk"])
        #expect(first.album == "Random Access Memories")
        #expect(first.duration == 276.0)
    }

    @Test func `playlist page follows continuations and prefixes VL`() async throws {
        let transport = FixtureTransport()
        try transport.serve("browse", fixture: "browse_playlist")
        transport.serve("browse", data: Data("{}".utf8))
        let list = try await InnerTubeClient(transport: transport, credentials: nil).playlistTracks(
            browseId: "PLkT4Xs2qpKuWPSk0BhBnVraDs9AdTVfrl")
        #expect(list.tracks.count == 19)
        #expect(transport.requests.count == 2)
        #expect(list.tracks.first?.album == "Random Access Memories")
        #expect(list.tracks.first?.duration == 276.0)
        let first = try #require(
            transport.requests.first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        )
        #expect(first["browseId"] as? String == "VLPLkT4Xs2qpKuWPSk0BhBnVraDs9AdTVfrl")
        let body = try transport.lastBody()
        #expect(body["continuation"] is String)
    }

    @Test func `artist page follows the songs playlist link`() async throws {
        let transport = FixtureTransport()
        try transport.serve("browse", fixture: "browse_artist")
        try transport.serve("browse", fixture: "browse_playlist")
        transport.serve("browse", data: Data("{}".utf8))
        let list = try await InnerTubeClient(transport: transport, credentials: nil).artistTracks(
            browseId: "UCRr1xG_2WIDs18a6cIiCxeA")
        #expect(list.title == "Daft Punk")
        #expect(list.tracks.count == 19)
        let second = try transport.requests[1].httpBody.map {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        #expect(second??["browseId"] as? String == "VLOLAK5uy_lNVBcjNtiCwq-n95uoxJ-Gd4vsfMkyZNs")
    }

    @Test func `artist page falls back to top songs`() throws {
        let url = try #require(
            Bundle.module.url(forResource: "browse_artist", withExtension: "json", subdirectory: "Fixtures"))
        let root = try JSON.parse(try Data(contentsOf: url))
        let tracks = Parsers.pageTracks(root, fallbackAlbum: nil)
        #expect(tracks.count == 5)
        #expect(tracks.first?.title.hasPrefix("Instant Crush") == true)
        #expect(tracks.first?.artists == ["Daft Punk", "Julian Casablancas"])
        #expect(tracks.first?.album == "Random Access Memories")
    }

    @Test func `radio excludes the seed track`() async throws {
        let transport = FixtureTransport()
        try transport.serve("next", fixture: "next_radio")
        let tracks = try await InnerTubeClient(transport: transport, credentials: nil).radio(for: "NOMa56y_Was")
        #expect(tracks.count == 49)
        #expect(!tracks.contains { $0.videoId == "NOMa56y_Was" })
        let first = try #require(tracks.first)
        #expect(first.title.hasPrefix("The Son of Flynn"))
        #expect(first.artists == ["Daft Punk"])
        #expect(first.duration == 96.0)
        let body = try transport.lastBody()
        #expect(body["playlistId"] as? String == "RDAMVMNOMa56y_Was")
    }

    @Test func `authenticated requests carry cookie, authorization and auth user`() async throws {
        let transport = FixtureTransport()
        try transport.serve("search", fixture: "search_songs")
        let creds = Credentials(cookie: "SAPISID=abc; SID=x", authUser: "0")
        _ = try await InnerTubeClient(transport: transport, credentials: creds).search("x", filter: .songs)
        let request = try #require(transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "Cookie") == "SAPISID=abc; SID=x")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
        #expect(request.value(forHTTPHeaderField: "X-Goog-AuthUser") == "0")
    }

    @Test func `anonymous requests carry no credentials`() async throws {
        let transport = FixtureTransport()
        try transport.serve("search", fixture: "search_songs")
        _ = try await InnerTubeClient(transport: transport, credentials: nil).search("x", filter: .songs)
        let request = try #require(transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func `liked songs browse the feed id without a VL prefix`() async throws {
        let transport = FixtureTransport()
        try transport.serve("browse", fixture: "browse_playlist")
        transport.serve("browse", data: Data("{}".utf8))
        let client = InnerTubeClient(transport: transport, credentials: Credentials(cookie: "SAPISID=a"))
        _ = try await client.likedSongs()
        let first = try #require(
            transport.requests.first?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        )
        #expect(first["browseId"] as? String == "FEmusic_liked_videos")
    }

    @Test func `session validation rejects a signed-out response`() async throws {
        let signedOut = """
            {"responseContext":{"serviceTrackingParams":[
               {"service":"GFEEDBACK","params":[{"key":"logged_in","value":"0"}]}]},
             "contents":{"messageRenderer":{"text":{"runs":[{"text":"Sign in"}]}}}}
            """
        let transport = FixtureTransport()
        transport.serve("browse", data: Data(signedOut.utf8))
        let client = InnerTubeClient(transport: transport, credentials: Credentials(cookie: "SAPISID=a"))
        await #expect(throws: YTMError.self) { try await client.validateSession() }
    }

    @Test func `session validation accepts a signed-in response`() async throws {
        let signedIn = """
            {"responseContext":{"serviceTrackingParams":[
               {"service":"GFEEDBACK","params":[{"key":"logged_in","value":"1"}]}]},
             "contents":{}}
            """
        let transport = FixtureTransport()
        transport.serve("browse", data: Data(signedIn.utf8))
        let client = InnerTubeClient(transport: transport, credentials: Credentials(cookie: "SAPISID=a"))
        try await client.validateSession()
        #expect(Parsers.isSignedIn(JSON(["contents": ["gridRenderer": [:]]])))
        #expect(!Parsers.isSignedIn(JSON(["contents": ["messageRenderer": [:]]])))
    }

    @Test func `library requests require login`() async throws {
        let client = InnerTubeClient(transport: FixtureTransport(), credentials: nil)
        await #expect(throws: YTMError.self) { try await client.likedSongs() }
    }

    @Test func `a redirect off music.youtube.com means the session expired`() async throws {
        struct Redirecting: HTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                (
                    Data(),
                    HTTPURLResponse(
                        url: URL(string: "https://accounts.google.com/x")!, statusCode: 200, httpVersion: nil,
                        headerFields: nil)!
                )
            }
        }
        let client = InnerTubeClient(transport: Redirecting(), credentials: Credentials(cookie: "SAPISID=a"))
        do {
            _ = try await client.libraryPlaylists()
            Issue.record("expected failure")
        } catch let error as YTMError {
            guard case .sessionExpired = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func `library artists follow continuations and de-duplicate`() async throws {
        let transport = FixtureTransport()
        try transport.serve("browse", fixture: "browse_library_artists")
        try transport.serve("browse", fixture: "browse_library_artists_page2")
        let client = InnerTubeClient(transport: transport, credentials: Credentials(cookie: "SAPISID=a"))
        let artists = try await client.libraryArtists()
        #expect(artists.map(\.name) == ["Example Artist One", "Example Artist Two", "Example Artist Three"])
        #expect(artists.first?.subtitle == "12K subscribers")
        #expect(transport.requests.count == 2)
        let second = try #require(transport.requests.last?.url)
        #expect(second.query?.contains("ctoken=CONT1") == true)
        #expect(second.query?.contains("type=next") == true)
    }

    @Test func `library albums parse the grid`() async throws {
        let transport = FixtureTransport()
        try transport.serve("browse", fixture: "browse_library_albums")
        let client = InnerTubeClient(transport: transport, credentials: Credentials(cookie: "SAPISID=a"))
        let albums = try await client.libraryAlbums()
        #expect(albums.count == 2)
        let first = try #require(albums.first)
        #expect(first.browseId == "MPREb_fake01")
        #expect(first.title == "Example Album")
        #expect(first.artists == ["Example Artist One"])
        #expect(first.year == "2019")
        let body = try transport.lastBody()
        #expect(body["browseId"] as? String == "FEmusic_liked_albums")
    }

    @Test func `library browsing requires a session`() async throws {
        let client = InnerTubeClient(transport: FixtureTransport(), credentials: nil)
        await #expect(throws: YTMError.self) { try await client.libraryArtists() }
        await #expect(throws: YTMError.self) { try await client.libraryAlbums() }
    }

    @Test func `duration parsing and formatting`() {
        #expect(Parsers.parseDuration("3:45") == 225)
        #expect(Parsers.parseDuration("1:02:03") == 3723)
        #expect(Parsers.parseDuration("12:00") == 720)
        #expect(Parsers.parseDuration("2013") == nil)
        #expect(Parsers.parseDuration("3:4") == nil)
        #expect(Parsers.parseDuration("") == nil)
        #expect(Parsers.parseDuration(nil) == nil)
        #expect(formatDuration(225) == "3:45")
        #expect(formatDuration(3723) == "1:02:03")
        #expect(formatDuration(nil) == "--:--")
    }

    @Test func `client version is derived from the UTC date`() {
        let v = InnerTubeClient.clientVersion(now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(v == "1.20231114.01.00")
    }
}
