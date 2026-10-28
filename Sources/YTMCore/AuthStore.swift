import Foundation

/// Reads and writes credentials to a file only the current user can read.
public struct AuthStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/ytm-cli/auth.json`
    public static func `default`() -> AuthStore {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return AuthStore(
            fileURL: base.appendingPathComponent("ytm-cli", isDirectory: true).appendingPathComponent("auth.json"))
    }

    public func load() throws -> Credentials? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode(Credentials.self, from: data)
        } catch {
            throw YTMError.io("Stored credentials at \(fileURL.path) are unreadable; run `ytm login` again.")
        }
    }

    public func save(_ credentials: Credentials) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let data = try JSONEncoder().encode(credentials)
        // Write to a sibling temp file with restricted permissions, then rename
        // atomically so the credentials are never observable with wider permissions.
        let tmp = dir.appendingPathComponent(".auth.json.\(getpid()).tmp")
        guard
            FileManager.default.createFile(
                atPath: tmp.path, contents: data,
                attributes: [.posixPermissions: 0o600])
        else {
            throw YTMError.io("Could not write \(tmp.path)")
        }
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw YTMError.io("Could not save credentials to \(fileURL.path): \(error.localizedDescription)")
        }
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
