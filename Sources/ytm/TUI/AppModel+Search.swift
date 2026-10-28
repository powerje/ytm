import Foundation
import YTMCore
import YTMPlayer

extension AppModel {
    // MARK: - Search and library

    func runSearch() {
        let query = state.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        let filter = state.filter
        searchTask?.cancel()
        state.busy = "Searching \(filter.rawValue) for “\(query)”…"
        searchTask = Task { [client] in
            do {
                let results = try await client.search(query, filter: filter)
                guard !Task.isCancelled else { return }
                showResults(results, title: "\(filter.title) · \(query)")
            } catch {
                guard !Task.isCancelled else { return }
                state.busy = nil
                show("Search failed: \(error)")
            }
            render()
        }
    }

    func showResults(_ results: [SearchResult], title: String) {
        state.results = results
        state.resultsTitle = title
        state.hasLoadedResults = true
        state.resultsCursor = ListCursor()
        state.pane = .results
        state.busy = nil
        if results.isEmpty { show("No results.") }
    }

    /// Shows the signed-in user's library for a filter: liked songs, library
    /// artists, saved albums or own playlists.
    func loadLibrary(_ filter: SearchFilter) {
        guard requireLogin() else { return }
        state.filter = filter
        let title = Self.libraryTitle(filter)
        state.busy = "Loading \(title.lowercased())…"
        searchTask?.cancel()
        searchTask = Task { [client] in
            do {
                let results: [SearchResult]
                switch filter {
                case .songs: results = try await client.likedSongs().tracks.map(SearchResult.track)
                case .artists: results = try await client.libraryArtists().map(SearchResult.artist)
                case .albums: results = try await client.libraryAlbums().map(SearchResult.album)
                case .playlists: results = try await client.libraryPlaylists().map(SearchResult.playlist)
                }
                guard !Task.isCancelled else { return }
                showResults(results, title: title)
            } catch {
                guard !Task.isCancelled else { return }
                state.busy = nil
                show("Could not load \(title.lowercased()): \(error)")
            }
            render()
        }
    }

    static func libraryTitle(_ filter: SearchFilter) -> String {
        switch filter {
        case .songs: "Liked songs"
        case .artists: "Your artists"
        case .albums: "Your albums"
        case .playlists: "Your playlists"
        }
    }

    func requireLogin() -> Bool {
        if state.loggedIn { return true }
        show("Run `ytm login` to use your library.")
        return false
    }
}
