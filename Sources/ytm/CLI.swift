import Foundation
import YTMCore
import YTMPlayer

@main
struct CLI {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty {
            TUIRunner.run()
        }
        Task { @MainActor in
            do {
                try await dispatch(args)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                exit(1)
            }
        }
        while true {
            RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }

    static func dispatch(_ args: [String]) async throws {
        switch args.first {
        case "login":
            try await login()
        case "logout":
            try logout()
        case "doctor":
            try await doctor()
        case "debug":
            try await debug(Array(args.dropFirst()))
        case "help", "-h", "--help", nil:
            printUsage()
        case "version", "--version":
            print("ytm \(version)")
        default:
            printUsage()
            exit(2)
        }
    }

    static let version = "0.1.0"

    static func printUsage() {
        print(
            """
            ytm — YouTube Music in the terminal

            usage:
              ytm            start the player
              ytm login      sign in by pasting request headers from your browser
              ytm logout     delete stored credentials
              ytm doctor     check mpv and yt-dlp
              ytm help       show this message
            """)
    }

    // MARK: - login / logout

    static func login() async throws {
        let store = AuthStore.default()
        print(
            """
            Sign in with your browser session:

              1. Open https://music.youtube.com in your browser and make sure you are signed in.
              2. Open the developer tools (Cmd-Option-I) and select the Network tab.
              3. Type "youtubei" into the filter box, then click Library or Explore in
                 YouTube Music so a request appears, and select it.
              4. Right-click it, then Copy > Copy as cURL.
              5. Paste below and press Enter twice. (Or pipe it in: pbpaste | ytm login)

            """)
        let pasted = PasteReader.read()
        let credentials = try Credentials.parse(rawHeaders: pasted)
        print("Checking the session…")
        let client = InnerTubeClient(credentials: credentials)
        try await client.validateSession()
        try store.save(credentials)
        print("Signed in. Credentials saved to \(store.fileURL.path) (readable only by you).")
    }

    static func logout() throws {
        let store = AuthStore.default()
        try store.delete()
        print("Removed \(store.fileURL.path). Sign out of YouTube in your browser to invalidate the session itself.")
    }

    // MARK: - doctor

    static func doctor() async throws {
        var ok = true
        func report(_ label: String, _ value: String?, hint: String? = nil) {
            if let value {
                print("  \(label): \(value)")
            } else {
                ok = false
                print("  \(label): MISSING" + (hint.map { " — " + $0 } ?? ""))
            }
        }
        print("External tools")
        let mpv = ExternalTools.find(name: "mpv")
        let ytdlp = ExternalTools.find(name: "yt-dlp")
        report("mpv", mpv, hint: ExternalTools.installHint)
        report("yt-dlp", ytdlp, hint: ExternalTools.installHint)
        if let mpv {
            let r = try await ExternalTools.run(mpv, ["--no-config", "--version"], timeout: 15)
            report("mpv version", r.stdout.split(separator: "\n").first.map(String.init))
        }
        if let ytdlp {
            let r = try await ExternalTools.run(ytdlp, ["--ignore-config", "--version"], timeout: 15)
            report("yt-dlp version", r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            print("  probing stream extraction (this contacts YouTube)…")
            let probe = try await ExternalTools.run(
                ytdlp,
                ["--ignore-config", "-f", "bestaudio/best", "-g", "https://music.youtube.com/watch?v=dQw4w9WgXcQ"],
                timeout: 60)
            if probe.status == 0, probe.stdout.hasPrefix("http") {
                print("  stream extraction: ok")
            } else {
                ok = false
                let detail = probe.stderr.split(separator: "\n").last.map(String.init) ?? "exit status \(probe.status)"
                print("  stream extraction: FAILED — \(detail)")
                print("  Try: brew upgrade yt-dlp")
            }
        }
        print("Credentials")
        let store = AuthStore.default()
        if let credentials = try store.load() {
            print("  file: \(store.fileURL.path)")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: store.fileURL.path),
                let perms = attrs[.posixPermissions] as? Int
            {
                let mode = String(perms, radix: 8)
                print("  permissions: \(mode)" + (perms & 0o077 == 0 ? "" : " — WARNING: readable by other users"))
            }
            print("  checking session…")
            do {
                try await InnerTubeClient(credentials: credentials).validateSession()
                print("  session: ok")
            } catch {
                ok = false
                print("  session: \(error)")
            }
        } else {
            print("  not logged in (run `ytm login`)")
        }
        print(ok ? "All good." : "Some checks failed.")
        if !ok { exit(1) }
    }

    // MARK: - debug

    static func printLibrary(_ kind: String, client: InnerTubeClient) async throws {
        switch kind {
        case "liked":
            let list = try await client.likedSongs()
            print("# \(list.title) (\(list.tracks.count) tracks)")
            for t in list.tracks { print("\(t.videoId)  \(formatDuration(t.duration))  \(t.title) — \(t.artistLine)") }
        case "playlists":
            for p in try await client.libraryPlaylists() {
                print("\(p.browseId)  \(p.title)" + (p.subtitle.map { "  (\($0))" } ?? ""))
            }
        case "artists":
            for a in try await client.libraryArtists() {
                print("\(a.browseId)  \(a.name)" + (a.subtitle.map { "  (\($0))" } ?? ""))
            }
        default:
            for a in try await client.libraryAlbums() {
                let artists = a.artists.joined(separator: ", ")
                print("\(a.browseId)  \(a.title) — \(artists)" + (a.year.map { "  (\($0))" } ?? ""))
            }
        }
    }

    static func debug(_ args: [String]) async throws {
        let store = AuthStore.default()
        let client = InnerTubeClient(credentials: try store.load())
        func printTracks(_ list: TrackList) {
            print("# \(list.title) (\(list.tracks.count) tracks)")
            for (i, t) in list.tracks.enumerated() {
                print(
                    String(
                        format: "%3d  %@  %@ — %@%@", i + 1, formatDuration(t.duration), t.title, t.artistLine,
                        t.album.map { "  [\($0)]" } ?? ""))
            }
        }
        switch args.first {
        case "search":
            let filter = SearchFilter(rawValue: args.dropFirst().first ?? "") ?? .songs
            let query = args.dropFirst(2).joined(separator: " ")
            for r in try await client.search(query, filter: filter) {
                switch r {
                case .track(let t):
                    print(
                        "song     \(t.videoId)  \(formatDuration(t.duration))  \(t.title) — \(t.artistLine)"
                            + (t.album.map { "  [\($0)]" } ?? ""))
                case .artist(let a): print("artist   \(a.browseId)  \(a.name)" + (a.subtitle.map { "  (\($0))" } ?? ""))
                case .album(let a):
                    print(
                        "album    \(a.browseId)  \(a.title) — \(a.artists.joined(separator: ", "))"
                            + (a.year.map { "  (\($0))" } ?? ""))
                case .playlist(let p):
                    print("playlist \(p.browseId)  \(p.title)" + (p.subtitle.map { "  (\($0))" } ?? ""))
                }
            }
        case "album": printTracks(try await client.albumTracks(browseId: args[1]))
        case "artist": printTracks(try await client.artistTracks(browseId: args[1]))
        case "playlist": printTracks(try await client.playlistTracks(browseId: args[1]))
        case "liked", "playlists", "artists", "albums": try await printLibrary(args[0], client: client)
        case "radio": printTracks(TrackList(title: "Radio", tracks: try await client.radio(for: args[1])))
        case "play":
            // Plays one video id for a few seconds through mpv, printing events.
            let tools = try ExternalTools.locate()
            let player = MpvPlayer(tools: tools)
            try await player.start(initialVolume: 50)
            try await player.load(Track(videoId: args[1], title: args[1], artists: []))
            let deadline = Date().addingTimeInterval(Double(args.dropFirst(2).first ?? "") ?? 12)
            for await event in player.events {
                print(event)
                if Date() > deadline { break }
                if case .ended = event { break }
                if case .processExited = event { break }
            }
            await player.shutdown()
        default:
            print(
                """
                debug subcommands:
                  search <songs|artists|albums|playlists> <query>
                  album <id> | artist <id> | playlist <id> | radio <videoId>
                  liked | playlists | artists | albums
                  play <videoId> [seconds]
                """)
        }
    }
}
