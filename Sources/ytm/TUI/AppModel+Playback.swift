import Foundation
import YTMCore
import YTMPlayer

extension AppModel {
    // MARK: - Queue actions

    func activateSelection() {
        switch state.pane {
        case .queue:
            guard state.queue.jump(to: state.queueCursor.selection) != nil else { return }
            playCurrent()
        case .results:
            guard let result = selectedResult else { return }
            if case .track(let track) = result {
                state.queue.playNext(track)
                state.queue.advance()
                followPlayingTrack()
                playCurrent()
            } else {
                fetchTracks(for: result, busy: "Loading") { [self] list in
                    guard !list.tracks.isEmpty else {
                        show("\(list.title) has no playable tracks.")
                        return
                    }
                    state.queue.replace(with: list.tracks)
                    state.queueCursor = ListCursor()
                    playCurrent()
                }
            }
        }
    }

    func appendSelection() {
        guard state.pane == .results, let result = selectedResult else { return }
        if case .track(let track) = result {
            state.queue.append(track)
            show("Added “\(track.title)” to the queue.")
            startIfIdle()
        } else {
            fetchTracks(for: result, busy: "Adding") { [self] list in
                state.queue.append(list.tracks)
                show("Added \(list.tracks.count) tracks from \(list.title).")
                startIfIdle()
            }
        }
    }

    func openSelection() {
        guard state.pane == .results, let result = selectedResult, !isTrack(result) else { return }
        fetchTracks(for: result, busy: "Opening") { [self] list in
            showResults(list.tracks.map(SearchResult.track), title: list.title)
        }
    }

    func isTrack(_ result: SearchResult) -> Bool {
        if case .track = result { return true }
        return false
    }

    func fetchTracks(
        for result: SearchResult, busy verb: String, then apply: @escaping @MainActor (TrackList) -> Void
    ) {
        fetchTask?.cancel()
        state.busy = "\(verb) \(resultTitle(result))…"
        fetchTask = Task { [client] in
            do {
                let list: TrackList
                switch result {
                case .track(let t): list = TrackList(title: t.title, tracks: [t])
                case .artist(let a): list = try await client.artistTracks(browseId: a.browseId)
                case .album(let a): list = try await client.albumTracks(browseId: a.browseId)
                case .playlist(let p): list = try await client.playlistTracks(browseId: p.browseId)
                }
                guard !Task.isCancelled else { return }
                state.busy = nil
                apply(list)
            } catch {
                guard !Task.isCancelled else { return }
                state.busy = nil
                show("Could not load \(resultTitle(result)): \(error)")
            }
            render()
        }
    }

    func resultTitle(_ result: SearchResult) -> String {
        switch result {
        case .track(let t): return t.title
        case .artist(let a): return a.name
        case .album(let a): return a.title
        case .playlist(let p): return p.title
        }
    }

    func removeSelectedFromQueue() {
        guard state.pane == .queue, !state.queue.isEmpty else { return }
        let index = state.queueCursor.selection
        if index == state.queue.index {
            show("Cannot remove the playing track; press n to skip it.")
            return
        }
        state.queue.remove(at: index)
        state.queueCursor.clamp(count: state.queue.count, visibleRows: state.listRows)
    }

    func clearQueue() {
        state.queue.clear()
        state.queueCursor = ListCursor()
        state.playback.timePos = nil
        state.playback.duration = nil
        Task { [player] in try? await player.stop() }
        show("Queue cleared.")
    }

    // MARK: - Playback

    func playCurrent() {
        guard let track = state.queue.current else { return }
        state.playback.loading = true
        state.message = nil
        Task { [player] in
            do {
                try await player.load(track)
            } catch {
                show("Could not play: \(error)")
                render()
            }
        }
    }

    /// Starts playback when something was added to an idle queue.
    func startIfIdle() {
        guard state.queue.current == nil || (state.playback.duration == nil && !state.playback.loading) else { return }
        if state.queue.current == nil { state.queue.advance() }
        followPlayingTrack()
        playCurrent()
    }

    func followPlayingTrack() {
        guard let index = state.queue.index, state.pane != .queue else { return }
        state.queueCursor.jump(to: index, count: state.queue.count, visibleRows: state.listRows)
    }

    func togglePause() {
        if state.playback.duration == nil, !state.playback.loading {
            startIfIdle()
            return
        }
        Task { [player] in try? await player.togglePause() }
    }

    func next(auto: Bool) {
        if state.queue.advance() != nil {
            followPlayingTrack()
            playCurrent()
        } else if state.radio, let seed = state.queue.current ?? state.queue.tracks.last {
            continueWithRadio(seed: seed)
        } else {
            state.playback.timePos = nil
            state.playback.duration = nil
            if !auto { show("End of queue.") }
            Task { [player] in try? await player.stop() }
        }
    }

    func previous() {
        if let t = state.playback.timePos, t > 3 {
            seek(by: -t)
            return
        }
        guard state.queue.goBack() != nil else { return }
        followPlayingTrack()
        playCurrent()
    }

    func continueWithRadio(seed: Track) {
        state.busy = "Finding more like “\(seed.title)”…"
        fetchTask?.cancel()
        fetchTask = Task { [client] in
            do {
                let known = Set(state.queue.tracks.map(\.videoId))
                let tracks = try await client.radio(for: seed.videoId).filter { !known.contains($0.videoId) }
                guard !Task.isCancelled else { return }
                state.busy = nil
                guard !tracks.isEmpty else {
                    show("Radio found nothing new.")
                    return
                }
                state.queue.append(tracks)
                if state.queue.advance() != nil {
                    followPlayingTrack()
                    playCurrent()
                }
            } catch {
                guard !Task.isCancelled else { return }
                state.busy = nil
                show("Radio failed: \(error)")
            }
            render()
        }
    }

    func seek(by seconds: Double) {
        guard state.playback.duration != nil else { return }
        Task { [player] in try? await player.seek(by: seconds) }
    }

    func adjustVolume(by delta: Double) {
        let target = min(max(state.playback.volume + delta, 0), 100)
        state.playback.volume = target
        Task { [player] in try? await player.setVolume(target) }
    }

    // MARK: - Media keys

    func handle(remote command: MediaRemote.Command) {
        switch command {
        case .play:
            if state.playback.paused { togglePause() } else { startIfIdle() }
        case .pause:
            if !state.playback.paused, state.playback.duration != nil { togglePause() }
        case .togglePlayPause:
            togglePause()
        case .next:
            next(auto: false)
        case .previous:
            previous()
        case .seek(let position):
            Task { [player] in try? await player.seek(to: position) }
        case .skip(let seconds):
            seek(by: seconds)
        }
        render()
    }

    private func publishNowPlaying() {
        let playing = state.playback.duration != nil || state.playback.loading
        mediaRemote?.update(track: playing ? state.queue.current : nil, playback: state.playback)
    }

    // MARK: - Player events

    func handle(playerEvent event: PlayerEvent) {
        switch event {
        case .state(let playback):
            let old = state.playback
            state.playback = playback
            publishNowPlaying()
            let secondChanged = Int(old.timePos ?? -1) != Int(playback.timePos ?? -1)
            if secondChanged || old.duration != playback.duration || old.paused != playback.paused
                || old.volume != playback.volume || old.loading != playback.loading
            {
                render()
            }
        case .fileLoaded:
            publishNowPlaying()
            render()
        case .ended(let reason):
            switch reason {
            case "eof":
                next(auto: true)
            case "error":
                let title = state.queue.current?.title ?? "track"
                show("Could not play “\(title)”, skipping.")
                next(auto: true)
            default:
                break
            }
            render()
        case .error(let text):
            show(text)
            render()
        case .processExited:
            state.playback = PlaybackState()
            publishNowPlaying()
            show("mpv exited. Press q and restart ytm.")
            render()
        }
    }
}
