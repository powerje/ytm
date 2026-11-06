import Foundation

/// Locates the external programs playback depends on. Nothing is downloaded
/// or installed; the user installs them (for example with Homebrew).
public struct ExternalTools: Sendable {
    public let mpv: String
    public let ytdlp: String

    public init(mpv: String, ytdlp: String) {
        self.mpv = mpv
        self.ytdlp = ytdlp
    }

    public static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    public static let installHint = "Install them with: brew install mpv yt-dlp"

    public static func find(
        name: String, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        var candidates: [String] = []
        if let override = environment["YTM_" + name.uppercased().replacingOccurrences(of: "-", with: "_")],
            !override.isEmpty
        {
            candidates.append(override)
        }
        let pathDirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in pathDirs + searchDirectories {
            candidates.append(dir + "/" + name)
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    public static func locate() throws -> ExternalTools {
        guard let mpv = find(name: "mpv") else {
            throw ToolError.missing("mpv")
        }
        guard let ytdlp = find(name: "yt-dlp") else {
            throw ToolError.missing("yt-dlp")
        }
        return ExternalTools(mpv: mpv, ytdlp: ytdlp)
    }

    public enum ToolError: Error, CustomStringConvertible {
        case missing(String)

        public var description: String {
            switch self {
            case .missing(let name):
                return "\(name) not found on PATH, /opt/homebrew/bin or /usr/local/bin. \(ExternalTools.installHint)"
            }
        }
    }

    public struct ProcessResult: Sendable {
        public let stdout: String
        public let stderr: String
        public let status: Int32
        /// The program was killed because it exceeded the timeout; the
        /// output is whatever it had written by then.
        public let timedOut: Bool
    }

    /// Runs a program with arguments and returns its stdout, stderr and exit status.
    public static func run(
        _ path: String, _ arguments: [String], timeout: TimeInterval = 60
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let box = ProcessBox(process)
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            box.terminate(timedOut: true)
        }
        defer { watchdog.cancel() }
        // Drain both pipes concurrently, off the cooperative pool
        // (readDataToEndOfFile blocks), so a program that fills one pipe
        // before closing the other cannot stall. Cancelling the calling task
        // kills the process instead of letting it run to completion for nobody.
        let (stdout, stderr): (Data, Data) = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let group = DispatchGroup()
                let drained = DrainedOutput()
                group.enter()
                DispatchQueue.global().async {
                    drained.stdout = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    drained.stderr = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.notify(queue: .global()) {
                    continuation.resume(returning: (drained.stdout, drained.stderr))
                }
            }
        } onCancel: {
            box.terminate(timedOut: false)
        }
        box.waitUntilExit()
        try Task.checkCancellation()
        return ProcessResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            status: box.status,
            timedOut: box.timedOut)
    }
}

/// `Process` is not Sendable; access is serialized with a lock.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var killedByTimeout = false

    init(_ process: Process) { self.process = process }

    func terminate(timedOut: Bool) {
        lock.withLock {
            guard process.isRunning else { return }
            if timedOut { killedByTimeout = true }
            process.terminate()
        }
    }

    func waitUntilExit() { process.waitUntilExit() }
    var status: Int32 { process.terminationStatus }
    var timedOut: Bool { lock.withLock { killedByTimeout } }
}

/// Written by the two drain queues, read after both have finished.
private final class DrainedOutput: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}
