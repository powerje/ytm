import Foundation
import MediaPlayer
import YTMCore
import YTMPlayer

/// Media keys (play/pause, next, previous, scrubbing) and the system
/// Now Playing panel, through the MediaPlayer framework.
@MainActor
final class MediaRemote {
    enum Command: Sendable {
        case play, pause, togglePlayPause, next, previous
        case seek(to: Double)
        case skip(by: Double)
    }

    private let handler: @MainActor (Command) -> Void
    private let center = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private var lastTrackId: String?
    private var lastPaused: Bool?
    private var lastReportedPosition: Double?
    private var lastReportedAt = Date.distantPast

    init(handler: @escaping @MainActor (Command) -> Void) {
        self.handler = handler
        register(center.playCommand, .play)
        register(center.pauseCommand, .pause)
        register(center.togglePlayPauseCommand, .togglePlayPause)
        register(center.nextTrackCommand, .next)
        register(center.previousTrackCommand, .previous)
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        register(center.skipForwardCommand, .skip(by: 10))
        register(center.skipBackwardCommand, .skip(by: -10))
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.dispatch(.seek(to: event.positionTime))
            return .success
        }
    }

    private func register(_ command: MPRemoteCommand, _ value: Command) {
        command.isEnabled = true
        command.addTarget { [weak self] _ in
            self?.dispatch(value)
            return .success
        }
    }

    private nonisolated func dispatch(_ command: Command) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.handler(command)
            }
        }
    }

    /// Publishes the current track and position. Cheap to call often: the
    /// system extrapolates elapsed time from the playback rate, so the info
    /// is only rewritten when something other than the clock changed.
    func update(track: Track?, playback: PlaybackState) {
        guard let track else {
            if lastTrackId != nil {
                infoCenter.nowPlayingInfo = nil
                infoCenter.playbackState = .stopped
                lastTrackId = nil
            }
            return
        }
        let position = playback.timePos ?? 0
        let expected = (lastReportedPosition ?? 0) + (lastPaused == true ? 0 : Date().timeIntervalSince(lastReportedAt))
        let drifted = abs(position - expected) > 2
        guard track.videoId != lastTrackId || playback.paused != lastPaused || drifted else { return }
        lastTrackId = track.videoId
        lastPaused = playback.paused
        lastReportedPosition = position
        lastReportedAt = Date()
        infoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistLine,
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPMediaItemPropertyPlaybackDuration: playback.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playback.paused ? 0.0 : 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        infoCenter.playbackState = playback.paused ? .paused : .playing
    }
}
