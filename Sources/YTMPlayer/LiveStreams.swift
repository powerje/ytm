import Foundation
import YTMCore

/// A YouTube channel whose live streams are listed with yt-dlp. No account
/// is involved: the streams tab is public.
public struct LiveChannel: Sendable {
    public let name: String
    public let streamsURL: String
    /// Streams to pin to the top of the list, in order. A stream matches an
    /// entry when its title contains every word of the entry (case-insensitive).
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
}

public enum LiveStreams {
    /// The channel's streams that are live right now, favorites first and
    /// the rest in the order the channel lists them. Stream ids change every
    /// time a stream is restarted, so they are looked up rather than stored.
    public static func list(_ channel: LiveChannel, tools: ExternalTools) async throws -> [Track] {
        let result = try await ExternalTools.run(
            tools.ytdlp,
            [
                "--ignore-config", "--no-warnings", "--flat-playlist", "--playlist-end", "60",
                "--print", "%(.{id,title,live_status})j", channel.streamsURL,
            ],
            timeout: 30)
        let tracks = parse(result.stdout, channel: channel)
        if tracks.isEmpty, result.status != 0 {
            let detail = result.stderr.split(separator: "\n").last.map(String.init) ?? "yt-dlp exited \(result.status)"
            throw YTMError.io(detail)
        }
        return tracks
    }

    /// Parses yt-dlp's output: one JSON object per line with `id`, `title`
    /// and `live_status`. Lines that are not JSON are skipped.
    static func parse(_ output: String, channel: LiveChannel) -> [Track] {
        var live: [Track] = []
        for line in output.split(separator: "\n") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["live_status"] as? String == "is_live",
                let id = object["id"] as? String, !id.isEmpty,
                let title = object["title"] as? String
            else { continue }
            live.append(
                Track(
                    videoId: id, title: title.trimmingCharacters(in: .whitespaces), artists: [channel.name],
                    isLive: true))
        }
        let pinned = channel.favorites.compactMap { words in
            live.first { track in
                let title = track.title.lowercased()
                return words.allSatisfy { title.contains($0.lowercased()) }
            }
        }
        return pinned + live.filter { track in !pinned.contains { $0.videoId == track.videoId } }
    }
}
