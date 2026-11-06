import Foundation
import YTMCore

/// A YouTube channel whose live streams are listed with yt-dlp. No account
/// is involved: the streams tab is public.
public struct LiveChannel: Sendable {
    public let name: String
    public let streamsURL: String
    /// Streams to pin to the top of the list, in order. A stream matches an
    /// entry when its title contains every phrase of the entry, ignoring case.
    /// The first live stream that matches is pinned. The first entry is the
    /// channel's main stream.
    public let favorites: [[String]]

    public init(name: String, streamsURL: String, favorites: [[String]]) {
        self.name = name
        self.streamsURL = streamsURL
        self.favorites = favorites
    }

    public static let lofiGirl = LiveChannel(
        name: "Lofi Girl",
        streamsURL: "https://www.youtube.com/@LofiGirl/streams",
        favorites: [
            ["lofi hip hop radio", "relax/study"],
            ["sleep lofi radio"],
            ["synthwave radio"],
            ["synth ambient radio"],
        ])

    public func matches(_ track: Track, favorite phrases: [String]) -> Bool {
        let title = track.title.lowercased()
        return phrases.allSatisfy { title.contains($0.lowercased()) }
    }

    /// Whether `track` is the channel's main stream (the first favorite).
    public func isPrimary(_ track: Track) -> Bool {
        guard let primary = favorites.first else { return false }
        return matches(track, favorite: primary)
    }
}

public enum LiveStreams {
    /// The channel's streams that are live right now, favorites first and
    /// the rest in the order the channel lists them. Stream ids change every
    /// time a stream is restarted, so they are looked up rather than stored.
    ///
    /// yt-dlp exits non-zero when any single entry fails, so a failure is
    /// only reported when it produced no streams at all. A timeout is always
    /// an error: a partial list could be missing the favorites.
    public static func list(
        _ channel: LiveChannel, tools: ExternalTools, timeout: TimeInterval = 30
    ) async throws -> [Track] {
        let result = try await ExternalTools.run(
            tools.ytdlp,
            [
                "--ignore-config", "--no-plugin-dirs", "--no-warnings", "--flat-playlist", "--playlist-end", "60",
                "--print", "%(.{id,title,live_status})j", channel.streamsURL,
            ],
            timeout: timeout)
        if result.timedOut {
            throw YTMError.io("yt-dlp did not answer within \(Int(timeout)) s.")
        }
        let parsed = parse(result.stdout, channel: channel)
        if parsed.tracks.isEmpty {
            if parsed.entriesWithoutStatus > 0 {
                throw YTMError.io("yt-dlp is too old to report which streams are live. Try: brew upgrade yt-dlp")
            }
            if result.status != 0 {
                let detail =
                    result.stderr.split(separator: "\n").last.map(String.init) ?? "yt-dlp exited \(result.status)"
                throw YTMError.io(detail)
            }
        }
        return parsed.tracks
    }

    struct Parsed {
        var tracks: [Track]
        /// Entries that had an id but no `live_status`, which old yt-dlp
        /// versions do not report for channel listings.
        var entriesWithoutStatus: Int
    }

    /// Parses yt-dlp's output: one JSON object per line with `id`, `title`
    /// and `live_status`. Lines that are not JSON are skipped, as are ids
    /// that do not look like YouTube video ids.
    static func parse(_ output: String, channel: LiveChannel) -> Parsed {
        var live: [Track] = []
        var withoutStatus = 0
        for line in output.split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                let id = object["id"] as? String, isVideoId(id)
            else { continue }
            guard let status = object["live_status"] as? String else {
                withoutStatus += 1
                continue
            }
            guard status == "is_live", let title = object["title"] as? String else { continue }
            live.append(
                Track(
                    videoId: id, title: terminalSafe(title).trimmingCharacters(in: .whitespaces),
                    artists: [channel.name], isLive: true))
        }
        var pinned: [Track] = []
        for phrases in channel.favorites {
            guard let match = live.first(where: { channel.matches($0, favorite: phrases) }),
                !pinned.contains(where: { $0.videoId == match.videoId })
            else { continue }
            pinned.append(match)
        }
        let rest = live.filter { track in !pinned.contains { $0.videoId == track.videoId } }
        return Parsed(tracks: pinned + rest, entriesWithoutStatus: withoutStatus)
    }

    static func isVideoId(_ id: String) -> Bool {
        id.count == 11
            && id.unicodeScalars.allSatisfy { scalar in
                scalar.properties.isASCIIHexDigit || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                    || scalar == "-" || scalar == "_"
            }
    }
}
