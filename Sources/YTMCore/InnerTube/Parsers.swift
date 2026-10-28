import Foundation

/// Parsers for the InnerTube renderers this app uses. Each parser is
/// defensive: a missing or reshaped field yields a skipped item or a nil
/// field, never a crash.
enum Parsers {
    // MARK: - Text runs

    private static let separator = " • "

    /// Parses "m:ss" or "h:mm:ss". Regex literals are checked at compile time
    /// and `Regex` is not `Sendable`, so the literal lives inline rather than
    /// in a stored static property.
    static func parseDuration(_ text: String?) -> TimeInterval? {
        guard let text = text?.trimmingCharacters(in: .whitespaces),
            let match = text.wholeMatch(of: /(?:(\d{1,2}):)?(\d{1,2}):(\d{2})/)
        else { return nil }
        let hours = match.1.flatMap { Int($0) } ?? 0
        guard let minutes = Int(match.2), let seconds = Int(match.3) else { return nil }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }

    /// Classifies the runs of a byline such as "Artist • Album • 3:45".
    struct Byline {
        var artists: [String] = []
        var album: String?
        var duration: TimeInterval?
    }

    static func parseByline(runs: [JSON], columnIndex: Int? = nil) -> Byline {
        var byline = Byline()
        var sawSeparator = false
        var unlabeled: [String] = []
        for run in runs {
            guard let text = run["text"].string else { continue }
            if text == separator { sawSeparator = true; continue }
            if let d = parseDuration(text) { byline.duration = d; continue }
            let browse = run["navigationEndpoint"]["browseEndpoint"]
            let pageType = browse["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"][
                "pageType"
            ].string
            let browseId = browse["browseId"].string ?? ""
            if pageType == "MUSIC_PAGE_TYPE_ARTIST" || pageType == "MUSIC_PAGE_TYPE_USER_CHANNEL"
                || browseId.hasPrefix("UC") || browseId.hasPrefix("MPLA")
            {
                byline.artists.append(text)
            } else if pageType == "MUSIC_PAGE_TYPE_ALBUM" || browseId.hasPrefix("MPREb") {
                byline.album = text
            } else if run["navigationEndpoint"].exists {
                continue
            } else {
                unlabeled.append((sawSeparator ? "\u{1}" : "") + text)
            }
        }
        // Runs without navigation endpoints: the first group before any
        // separator is artist text (possibly "A & B"), later groups are
        // metadata such as play counts or years that we drop.
        if byline.artists.isEmpty {
            let first = unlabeled.filter { !$0.hasPrefix("\u{1}") && !looksLikeMetadata($0) }
            if let text = first.first {
                byline.artists = text.components(separatedBy: " & ").flatMap { $0.components(separatedBy: ", ") }
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
        }
        return byline
    }

    static func isYear(_ text: String) -> Bool {
        text.wholeMatch(of: /\d{4}/) != nil
    }

    private static func looksLikeMetadata(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasSuffix(" plays") || lower.hasSuffix(" views") || lower.hasSuffix(" likes") { return true }
        if lower == "song" || lower == "video" || lower == "album" || lower == "single" || lower == "ep"
            || lower == "playlist"
        {
            return true
        }
        if isYear(text) { return true }
        return false
    }

    // MARK: - musicResponsiveListItemRenderer

    /// Parses a list item into a track. `fallbackAlbum` is used for album
    /// pages, where the album name is in the page header rather than the row.
    static func track(fromResponsiveItem item: JSON, fallbackAlbum: String? = nil) -> Track? {
        let columns = item["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"] }
        guard let titleRuns = columns.first?["runs"].array, let title = columns.first?.runsText, !title.isEmpty else {
            return nil
        }
        var videoId = item["playlistItemData"]["videoId"].string
        if videoId == nil {
            videoId = titleRuns.first?["navigationEndpoint"]["watchEndpoint"]["videoId"].string
        }
        if videoId == nil {
            videoId = item["overlay"].findFirst("watchEndpoint")?["videoId"].string
        }
        guard let videoId, !videoId.isEmpty else { return nil }

        var byline = Byline()
        for (i, column) in columns.enumerated() where i > 0 {
            let partial = parseByline(runs: column["runs"].array, columnIndex: i)
            byline.artists.append(contentsOf: partial.artists.filter { !byline.artists.contains($0) })
            if byline.album == nil { byline.album = partial.album }
            if byline.duration == nil { byline.duration = partial.duration }
        }
        if byline.duration == nil {
            for fixed in item["fixedColumns"].array {
                if let d = parseDuration(fixed["musicResponsiveListItemFixedColumnRenderer"]["text"].runsText) {
                    byline.duration = d
                    break
                }
            }
        }
        return Track(
            videoId: videoId, title: title, artists: byline.artists,
            album: byline.album ?? fallbackAlbum, duration: byline.duration)
    }

    static func artist(fromResponsiveItem item: JSON) -> Artist? {
        let columns = item["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"] }
        guard let name = columns.first?.runsText, !name.isEmpty,
            let browseId = item["navigationEndpoint"]["browseEndpoint"]["browseId"].string
        else { return nil }
        let subtitle = columns.dropFirst().first?.runsText
        return Artist(browseId: browseId, name: name, subtitle: cleanSubtitle(subtitle))
    }

    static func album(fromResponsiveItem item: JSON) -> Album? {
        let columns = item["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"] }
        guard let title = columns.first?.runsText, !title.isEmpty,
            let browseId = item["navigationEndpoint"]["browseEndpoint"]["browseId"].string
        else { return nil }
        let runs = columns.dropFirst().first?["runs"].array ?? []
        let byline = parseByline(runs: runs)
        let year = runs.compactMap { $0["text"].string }.first { isYear($0) }
        return Album(browseId: browseId, title: title, artists: byline.artists, year: year)
    }

    static func playlist(fromResponsiveItem item: JSON) -> Playlist? {
        let columns = item["flexColumns"].array.map { $0["musicResponsiveListItemFlexColumnRenderer"]["text"] }
        guard let title = columns.first?.runsText, !title.isEmpty,
            let browseId = item["navigationEndpoint"]["browseEndpoint"]["browseId"].string
        else { return nil }
        return Playlist(browseId: browseId, title: title, subtitle: cleanSubtitle(columns.dropFirst().first?.runsText))
    }

    private static func cleanSubtitle(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Other renderers

    /// `musicTwoRowItemRenderer` (library playlist grid).
    static func playlist(fromTwoRowItem item: JSON) -> Playlist? {
        guard let title = item["title"].runsText, !title.isEmpty,
            let browseId = item["navigationEndpoint"]["browseEndpoint"]["browseId"].string,
            browseId.hasPrefix("VL")
        else { return nil }
        return Playlist(browseId: browseId, title: title, subtitle: cleanSubtitle(item["subtitle"].runsText))
    }

    /// `musicTwoRowItemRenderer` (library album grid).
    static func album(fromTwoRowItem item: JSON) -> Album? {
        guard let title = item["title"].runsText, !title.isEmpty,
            let browseId = item["navigationEndpoint"]["browseEndpoint"]["browseId"].string,
            browseId.hasPrefix("MPRE")
        else { return nil }
        let runs = item["subtitle"]["runs"].array
        let byline = parseByline(runs: runs)
        let year = runs.compactMap { $0["text"].string }.first { isYear($0) }
        return Album(browseId: browseId, title: title, artists: byline.artists, year: year)
    }

    /// `playlistPanelVideoRenderer` (radio / watch queue).
    static func track(fromPanelVideo item: JSON) -> Track? {
        guard let videoId = item["videoId"].string, let title = item["title"].runsText, !title.isEmpty else {
            return nil
        }
        let byline = parseByline(runs: item["longBylineText"]["runs"].array)
        let duration = parseDuration(item["lengthText"].runsText)
        return Track(
            videoId: videoId, title: title, artists: byline.artists, album: byline.album,
            duration: duration ?? byline.duration)
    }

    // MARK: - Pages

    static func searchResults(_ root: JSON, filter: SearchFilter) -> [SearchResult] {
        var results: [SearchResult] = []
        var seen = Set<String>()
        for shelf in root.findAll("musicShelfRenderer") {
            for entry in shelf["contents"].array {
                let item = entry["musicResponsiveListItemRenderer"]
                guard item.exists else { continue }
                let result: SearchResult?
                switch filter {
                case .songs: result = track(fromResponsiveItem: item).map(SearchResult.track)
                case .artists: result = artist(fromResponsiveItem: item).map(SearchResult.artist)
                case .albums: result = album(fromResponsiveItem: item).map(SearchResult.album)
                case .playlists: result = playlist(fromResponsiveItem: item).map(SearchResult.playlist)
                }
                if let result, seen.insert(result.id).inserted { results.append(result) }
            }
        }
        return results
    }

    static func pageTitle(_ root: JSON) -> String? {
        for key in [
            "musicResponsiveHeaderRenderer", "musicDetailHeaderRenderer", "musicImmersiveHeaderRenderer",
            "musicVisualHeaderRenderer", "musicEditablePlaylistDetailHeaderRenderer",
        ] {
            if let header = root.findFirst(key) {
                if let title = header["title"].runsText, !title.isEmpty { return title }
                if let title = header["header"].findFirst("title")?.runsText, !title.isEmpty { return title }
            }
        }
        return nil
    }

    /// Tracks listed on an album, playlist or liked-songs page (first page).
    static func pageTracks(_ root: JSON, fallbackAlbum: String?) -> [Track] {
        var tracks: [Track] = []
        var seen = Set<String>()
        for item in root.findAll("musicResponsiveListItemRenderer") {
            if let t = track(fromResponsiveItem: item, fallbackAlbum: fallbackAlbum), seen.insert(t.videoId).inserted {
                tracks.append(t)
            }
        }
        return tracks
    }

    /// Continuation token for the next page of a playlist, if any.
    static func continuationToken(_ root: JSON) -> String? {
        if let token = root.findFirst("continuationItemRenderer")?["continuationEndpoint"]["continuationCommand"][
            "token"
        ].string {
            return token
        }
        return root.findFirst("nextContinuationData")?["continuation"].string
    }

    /// Browse id of the artist's full "songs" playlist, from the Top songs shelf header.
    static func artistSongsPlaylistId(_ root: JSON) -> String? {
        for shelf in root.findAll("musicShelfRenderer") {
            if let id = shelf["title"]["runs"][0]["navigationEndpoint"]["browseEndpoint"]["browseId"].string,
                id.hasPrefix("VL")
            {
                return id
            }
        }
        return nil
    }

    static func radioTracks(_ root: JSON) -> [Track] {
        var tracks: [Track] = []
        var seen = Set<String>()
        for item in root.findAll("playlistPanelVideoRenderer") {
            if let t = track(fromPanelVideo: item), seen.insert(t.videoId).inserted { tracks.append(t) }
        }
        return tracks
    }

    /// Whether a response was produced for a signed-in user. YouTube reports
    /// `logged_in` in its tracking parameters; a library page for a signed-out
    /// request instead contains a sign-in message.
    static func isSignedIn(_ root: JSON) -> Bool {
        for service in root["responseContext"]["serviceTrackingParams"].array {
            for param in service["params"].array where param["key"].string == "logged_in" {
                return param["value"].string == "1"
            }
        }
        return root.findFirst("messageRenderer") == nil
    }

    static func libraryArtists(_ root: JSON) -> [Artist] {
        var artists: [Artist] = []
        var seen = Set<String>()
        for item in root.findAll("musicResponsiveListItemRenderer") {
            if let a = artist(fromResponsiveItem: item), a.browseId.hasPrefix("UC"), seen.insert(a.browseId).inserted {
                artists.append(a)
            }
        }
        return artists
    }

    static func libraryAlbums(_ root: JSON) -> [Album] {
        var albums: [Album] = []
        var seen = Set<String>()
        for item in root.findAll("musicTwoRowItemRenderer") {
            if let a = album(fromTwoRowItem: item), seen.insert(a.browseId).inserted { albums.append(a) }
        }
        return albums
    }

    static func libraryPlaylists(_ root: JSON) -> [Playlist] {
        var playlists: [Playlist] = []
        var seen = Set<String>()
        for item in root.findAll("musicTwoRowItemRenderer") {
            if let p = playlist(fromTwoRowItem: item), seen.insert(p.browseId).inserted { playlists.append(p) }
        }
        return playlists
    }
}
