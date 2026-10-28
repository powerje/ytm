import Foundation
import SwiftTUI
import YTMCore
import YTMPlayer

enum TUIRunner {
    /// Starts the terminal UI. Never returns; the process exits from the UI.
    @MainActor
    static func run() -> Never {
        let tools: ExternalTools
        do {
            tools = try ExternalTools.locate()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        let credentials: Credentials?
        do {
            credentials = try AuthStore.default().load()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            FileHandle.standardError.write(Data("error: ytm needs an interactive terminal\n".utf8))
            exit(1)
        }

        CrashGuard.install()
        let client = InnerTubeClient(credentials: credentials)
        let player = MpvPlayer(tools: tools)
        let store = ScreenStore()
        let model = AppModel(client: client, player: player, store: store)

        nonisolated(unsafe) let app = Application(rootView: RootView(store: store), runLoopType: .runLoop)
        app.keyHandler = { key in
            MainActor.assumeIsolated { model.handle(key: key) }
            return true
        }
        app.willStop = {
            // Everything that must happen on exit is done here explicitly;
            // _exit then skips library teardown, which can stall for seconds.
            Trace.log("willStop: begin")
            player.terminate()
            Application.restoreTerminal()
            Trace.log("willStop: exiting")
            _exit(0)
        }
        model.quit = { app.quit() }

        Task { @MainActor in
            await model.start()
        }
        app.start()
        exit(0)
    }
}
