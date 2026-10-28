import Darwin
import Foundation

/// Last-resort cleanup for fatal signals: stop mpv, remove its socket and
/// restore the terminal, then let the default handler produce the crash
/// report. Only async-signal-safe calls are made inside the handler.
enum CrashGuard {
    nonisolated(unsafe) private static var childPid: pid_t = 0
    nonisolated(unsafe) private static var socketPath: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) private static var savedTermios = termios()
    nonisolated(unsafe) private static var hasTermios = false

    static func install() {
        if tcgetattr(STDIN_FILENO, &savedTermios) == 0 { hasTermios = true }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE] {
            signal(sig, crashHandler)
        }
    }

    static func watch(childPid pid: pid_t, socketPath path: String) {
        childPid = pid
        socketPath?.deallocate()
        socketPath = strdup(path)
    }

    static func forget() {
        childPid = 0
    }
}

private let crashHandler: @convention(c) (Int32) -> Void = { sig in
    CrashGuard.handle(signal: sig)
}

extension CrashGuard {
    fileprivate static func handle(signal sig: Int32) {
        if childPid > 0 {
            kill(childPid, SIGTERM)
        }
        if let socketPath {
            unlink(socketPath)
        }
        if hasTermios {
            tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
        }
        let reset = "\u{1b}[?1049l\u{1b}[?25h\n"
        reset.withCString { _ = write(STDOUT_FILENO, $0, strlen($0)) }
        signal(sig, SIG_DFL)
        raise(sig)
    }
}
