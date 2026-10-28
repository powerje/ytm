import Foundation

/// Timestamped diagnostics on standard error, enabled by setting `YTM_TRACE`.
public enum Trace {
    public static let enabled = ProcessInfo.processInfo.environment["YTM_TRACE"] != nil

    public static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = String(format: "[%.3f] ", Date().timeIntervalSince1970) + message() + "\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
