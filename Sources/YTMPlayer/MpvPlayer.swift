import Foundation
import YTMCore

/// Playback state as reported by mpv.
public struct PlaybackState: Sendable, Equatable {
    public var timePos: Double?
    public var duration: Double?
    public var paused = false
    public var volume: Double = 100
    public var loading = false

    public init() {}
}

public enum PlayerEvent: Sendable, Equatable {
    case state(PlaybackState)
    case fileLoaded
    /// Playback of the current file ended. `reason` is mpv's end-file reason
    /// (`eof`, `error`, `stop`, `quit`, `redirect`).
    case ended(reason: String)
    case error(String)
    case processExited
}

/// Owns an `mpv` subprocess and talks to it over its JSON IPC socket.
///
/// mpv is launched with `--no-config` so no user configuration or scripts are
/// loaded, and with the bundled ytdl hook pointed at the located `yt-dlp`,
/// which is also told to ignore its own configuration files.
/// Owns the mpv process and its control socket. Shared between the player
/// actor and the synchronous `terminate()` used on exit paths.
final class MpvConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var socketFD: Int32 = -1
    let socketPath: String
    private var closed = false

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    var isConnected: Bool { lock.withLock { socketFD >= 0 } }

    var processIdentifier: pid_t? { lock.withLock { process.map { $0.processIdentifier } } }

    func attach(process: Process) {
        lock.withLock { self.process = process }
    }

    func attach(socket fd: Int32) {
        lock.withLock { socketFD = fd }
    }

    var fileDescriptor: Int32 { lock.withLock { socketFD } }

    func write(_ data: Data) throws {
        let fd = lock.withLock { socketFD }
        guard fd >= 0 else { throw YTMError.io("mpv is not running") }
        let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        if written != data.count {
            throw YTMError.io("could not write to mpv: \(String(cString: strerror(errno)))")
        }
    }

    /// Asks mpv to quit, waits briefly, then terminates it. Idempotent.
    func terminate() {
        let (process, fd): (Process?, Int32) = lock.withLock {
            guard !closed else { return (nil, -1) }
            closed = true
            let pair = (self.process, socketFD)
            self.process = nil
            socketFD = -1
            return pair
        }
        Trace.log("terminate: begin fd=\(fd) pid=\(process?.processIdentifier ?? 0)")
        if fd >= 0 {
            if let data = try? encodeMpvCommand(["quit"], requestId: 0) {
                _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            }
            // Closing alone does not wake a thread blocked in read() on
            // macOS; shutting the socket down first does, so the reader
            // thread exits and the process can terminate promptly.
            Darwin.shutdown(fd, SHUT_RDWR)
            close(fd)
        }
        Trace.log("terminate: socket closed")
        if let process, process.isRunning {
            let deadline = Date().addingTimeInterval(1.0)
            while process.isRunning, Date() < deadline {
                usleep(20_000)
            }
            if process.isRunning {
                Trace.log("terminate: mpv still running, sending SIGTERM")
                process.terminate()
            }
        }
        unlink(socketPath)
        Trace.log("terminate: done")
    }
}

/// Owns an `mpv` subprocess and talks to it over its JSON IPC socket.
///
/// mpv is launched with `--no-config` so no user configuration or scripts are
/// loaded, and with the bundled ytdl hook pointed at the located `yt-dlp`,
/// which is also told to ignore its own configuration files.
public actor MpvPlayer {
    public let tools: ExternalTools
    public nonisolated let events: AsyncStream<PlayerEvent>
    private let eventsContinuation: AsyncStream<PlayerEvent>.Continuation
    private let connection: MpvConnection

    private var reader: Thread?
    private var nextRequestId = 1
    private var state = PlaybackState()
    private var started = false

    public init(tools: ExternalTools) {
        self.tools = tools
        let dir = NSTemporaryDirectory()
        connection = MpvConnection(socketPath: (dir.hasSuffix("/") ? dir : dir + "/") + "ytm-\(getpid()).sock")
        (events, eventsContinuation) = AsyncStream.makeStream(of: PlayerEvent.self, bufferingPolicy: .unbounded)
    }

    public var currentState: PlaybackState { state }

    /// The mpv process id and socket path, for external cleanup on crashes.
    public nonisolated var processInfo: (pid: pid_t, socketPath: String)? {
        connection.processIdentifier.map { ($0, connection.socketPath) }
    }

    // MARK: - Lifecycle

    public func start(initialVolume: Double = 100) async throws {
        guard !started else { return }
        started = true
        let socketPath = connection.socketPath
        unlink(socketPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tools.mpv)
        process.arguments = [
            "--no-config",
            "--no-video",
            "--idle=yes",
            "--input-media-keys=no",
            "--no-terminal",
            "--really-quiet",
            "--keep-open=no",
            "--audio-display=no",
            "--volume=\(Int(initialVolume))",
            "--ytdl=yes",
            "--ytdl-format=bestaudio/best",
            "--script-opts=ytdl_hook-ytdl_path=\(tools.ytdlp),ytdl_hook-try_ytdl_first=yes",
            "--ytdl-raw-options=ignore-config=",
            "--input-ipc-server=\(socketPath)",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let continuation = eventsContinuation
        process.terminationHandler = { _ in continuation.yield(.processExited) }
        try process.run()
        connection.attach(process: process)

        // Wait for the socket to appear.
        var attempts = 0
        while !FileManager.default.fileExists(atPath: socketPath) {
            attempts += 1
            if attempts > 100 || !process.isRunning {
                throw YTMError.io("mpv did not create its control socket")
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        connection.attach(socket: try Self.connect(to: socketPath))
        startReader()
        try send(["observe_property", 1, "time-pos"])
        try send(["observe_property", 2, "duration"])
        try send(["observe_property", 3, "pause"])
        try send(["observe_property", 4, "volume"])
    }

    /// Stops mpv and removes the socket. Safe to call from any thread, more
    /// than once, and from synchronous exit paths.
    public nonisolated func terminate() {
        connection.terminate()
    }

    public func shutdown() {
        terminate()
        eventsContinuation.finish()
    }

    // MARK: - Commands

    public func load(_ track: Track) throws {
        state.loading = true
        state.timePos = nil
        state.duration = nil
        publishState()
        try send(["loadfile", track.watchURL.absoluteString, "replace"])
    }

    public func stop() throws {
        try send(["stop"])
    }

    public func setPaused(_ paused: Bool) throws {
        try send(["set_property", "pause", paused])
    }

    public func togglePause() throws {
        try send(["cycle", "pause"])
    }

    public func seek(by seconds: Double) throws {
        try send(["seek", seconds, "relative"])
    }

    public func seek(to seconds: Double) throws {
        try send(["seek", max(seconds, 0), "absolute"])
    }

    public func setVolume(_ volume: Double) throws {
        let clamped = min(max(volume, 0), 130)
        try send(["set_property", "volume", clamped])
    }

    // MARK: - Socket plumbing

    private static func connect(to socketPath: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw YTMError.io("socket() failed: \(String(cString: strerror(errno)))") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            close(fd)
            throw YTMError.io("socket path too long: \(socketPath)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + MemoryLayout<UInt8>.size + pathBytes.count + 1)
        var lastError: Int32 = 0
        for _ in 0..<40 {
            let result = withUnsafePointer(to: &addr) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
            }
            if result == 0 { return fd }
            lastError = errno
            usleep(50_000)
        }
        close(fd)
        throw YTMError.io("could not connect to mpv: \(String(cString: strerror(lastError)))")
    }

    private func send(_ command: [Any]) throws {
        let id = nextRequestId
        nextRequestId += 1
        try connection.write(try encodeMpvCommand(command, requestId: id))
    }

    private func startReader() {
        let fd = connection.fileDescriptor
        let thread = Thread { [weak self] in
            var decoder = MpvLineDecoder()
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                let messages = decoder.feed(Data(buffer[0..<count]))
                guard let self else { return }
                if !messages.isEmpty {
                    Task { await self.handle(messages) }
                }
            }
        }
        thread.name = "mpv-ipc-reader"
        thread.start()
        reader = thread
    }

    private func handle(_ messages: [MpvMessage]) {
        var stateChanged = false
        for message in messages {
            switch message {
            case .propertyChange(let name, let value):
                switch name {
                case "time-pos": state.timePos = value?.double
                case "duration": state.duration = value?.double
                case "pause": if let paused = value?.bool { state.paused = paused }
                case "volume": if let volume = value?.double { state.volume = volume }
                default: continue
                }
                stateChanged = true
            case .event(let name, let reason):
                switch name {
                case "file-loaded":
                    state.loading = false
                    stateChanged = true
                    eventsContinuation.yield(.fileLoaded)
                case "end-file":
                    state.loading = false
                    stateChanged = true
                    eventsContinuation.yield(.ended(reason: reason ?? "unknown"))
                default: break
                }
            case .reply(_, let error, _):
                if error != "success" { eventsContinuation.yield(.error("mpv: \(error)")) }
            }
        }
        if stateChanged { publishState() }
    }

    private func publishState() {
        eventsContinuation.yield(.state(state))
    }
}
