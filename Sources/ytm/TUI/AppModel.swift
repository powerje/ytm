import Foundation
import SwiftTUI
import YTMCore
import YTMPlayer

/// The controller: owns the screen state, reacts to keys and player events,
/// and talks to the API client and the player.
@MainActor
final class AppModel {
    var state = ScreenState()
    let client: InnerTubeClient
    let player: MpvPlayer
    let store: ScreenStore

    /// Set by the runner to stop the UI run loop.
    var quit: @MainActor () -> Void = {}

    var searchTask: Task<Void, Never>?
    var fetchTask: Task<Void, Never>?
    private var messageTask: Task<Void, Never>?
    private var resizeSource: DispatchSourceSignal?
    var mediaRemote: MediaRemote?

    init(client: InnerTubeClient, player: MpvPlayer, store: ScreenStore) {
        self.client = client
        self.player = player
        self.store = store
        state.loggedIn = client.isAuthenticated
        if !client.isAuthenticated {
            state.message = "Not logged in: library disabled. Run `ytm login`."
        }
        updateSize()
        render()
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            try await player.start(initialVolume: 60)
            if let info = player.processInfo {
                CrashGuard.watch(childPid: info.pid, socketPath: info.socketPath)
            }
        } catch {
            show("Could not start mpv: \(error)")
        }
        watchResize()
        mediaRemote = MediaRemote { [weak self] command in
            self?.handle(remote: command)
        }
        render()
        for await event in player.events {
            handle(playerEvent: event)
        }
    }

    private func watchResize() {
        signal(SIGWINCH, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateSize()
                self.render()
            }
        }
        source.resume()
        resizeSource = source
    }

    private func updateSize() {
        var size = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0, size.ws_row > 0 {
            state.width = Int(size.ws_col)
            state.height = Int(size.ws_row)
        }
        state.resultsCursor.clamp(count: state.results.count, visibleRows: state.listRows)
        state.queueCursor.clamp(count: state.queue.count, visibleRows: state.listRows)
    }

    func render() {
        store.set(Screen.render(state))
    }

    // MARK: - Keys

    func handle(key: KeyEvent) {
        switch state.mode {
        case .search: handleSearchKey(key)
        case .normal: handleNormalKey(key)
        }
        render()
    }

    private func handleSearchKey(_ key: KeyEvent) {
        switch key {
        case .character(let c):
            state.query.append(c)
        case .backspace:
            if !state.query.isEmpty { state.query.removeLast() }
        case .enter:
            state.mode = .normal
            runSearch()
        case .escape:
            state.mode = .normal
        default:
            break
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleNormalKey(_ key: KeyEvent) {
        switch key {
        case .character("/"):
            state.mode = .search
            state.message = nil
        case .character("q"):
            Trace.log("key q: quitting")
            quit()
        case .character("1"): setFilter(.songs)
        case .character("2"): setFilter(.artists)
        case .character("3"): setFilter(.albums)
        case .character("4"): setFilter(.playlists)
        case .character("j"), .down: move(by: 1)
        case .character("k"), .up: move(by: -1)
        case .pageDown, .character("d"): move(by: state.listRows)
        case .pageUp, .character("u"): move(by: -state.listRows)
        case .home, .character("g"): move(by: -Int.max / 2)
        case .end, .character("G"): move(by: Int.max / 2)
        case .tab:
            state.pane = state.pane == .results ? .queue : .results
        case .enter: activateSelection()
        case .character("a"): appendSelection()
        case .character("o"): openSelection()
        case .character("L"): loadLibrary(.songs)
        case .character("P"): loadLibrary(.playlists)
        case .character(" "): togglePause()
        case .character("n"): next(auto: false)
        case .character("p"): previous()
        case .character(","), .left: seek(by: -10)
        case .character("."), .right: seek(by: 10)
        case .character("<"): seek(by: -60)
        case .character(">"): seek(by: 60)
        case .character("-"), .character("_"): adjustVolume(by: -5)
        case .character("+"), .character("="): adjustVolume(by: 5)
        case .character("r"):
            state.radio.toggle()
        case .character("x"): removeSelectedFromQueue()
        case .character("C"): clearQueue()
        case .escape:
            state.message = nil
        default:
            break
        }
    }

    // MARK: - Navigation

    private func move(by delta: Int) {
        switch state.pane {
        case .results:
            state.resultsCursor.move(by: delta, count: state.results.count, visibleRows: state.listRows)
        case .queue:
            state.queueCursor.move(by: delta, count: state.queue.count, visibleRows: state.listRows)
        }
    }

    var selectedResult: SearchResult? {
        guard state.results.indices.contains(state.resultsCursor.selection) else { return nil }
        return state.results[state.resultsCursor.selection]
    }

    /// With a query entered, re-runs the search under the new filter. With an
    /// empty query the filter browses the user's library instead.
    private func setFilter(_ filter: SearchFilter) {
        if state.query.trimmingCharacters(in: .whitespaces).isEmpty {
            if state.loggedIn { loadLibrary(filter) } else { state.filter = filter }
            return
        }
        guard filter != state.filter else { return }
        state.filter = filter
        runSearch()
    }

    // MARK: - Messages

    func show(_ text: String) {
        state.message = text
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            if state.message == text {
                state.message = nil
                render()
            }
        }
    }
}
