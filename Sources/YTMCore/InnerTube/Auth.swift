import CryptoKit
import Foundation

/// Credentials pasted from a browser session on music.youtube.com.
///
/// Only the values needed to authenticate InnerTube requests are kept. The
/// struct never prints its contents.
public struct Credentials: Codable, Sendable, Equatable {
    /// Full `Cookie` request header value.
    public let cookie: String
    /// Value of the `X-Goog-AuthUser` header (account index), defaults to "0".
    public let authUser: String

    public init(cookie: String, authUser: String = "0") {
        self.cookie = cookie
        self.authUser = authUser
    }

    /// The SAPISID cookie value, used to sign requests.
    public var sapisid: String? {
        let pairs = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for name in ["SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID"] {
            if let pair = pairs.first(where: { $0.hasPrefix(name + "=") }) {
                let value = pair.dropFirst(name.count + 1)
                if !value.isEmpty { return String(value) }
            }
        }
        return nil
    }

    /// Parses raw request headers as copied from the browser's developer tools
    /// ("Copy request headers" or a curl command's `-H` lines also work).
    public static func parse(rawHeaders: String) throws -> Credentials {
        var cookie: String?
        var authUser = "0"
        for rawLine in rawHeaders.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // Tolerate lines copied from a curl command: -H 'name: value' \
            // and the cookie form Chrome emits: -b 'name=value; name2=value2' \
            for flag in ["-H ", "-b ", "--cookie ", "--header "] where line.hasPrefix(flag) {
                line = String(line.dropFirst(flag.count)).trimmingCharacters(in: .whitespaces)
                if line.hasSuffix("\\") { line = String(line.dropLast()).trimmingCharacters(in: .whitespaces) }
                if line.hasPrefix("'") || line.hasPrefix("\"") { line = String(line.dropFirst()) }
                if line.hasSuffix("'") || line.hasSuffix("\"") { line = String(line.dropLast()) }
                if flag == "-b " || flag == "--cookie " { line = "cookie: " + line }
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch name {
            case "cookie": cookie = value
            case "x-goog-authuser": authUser = value
            default: break
            }
        }
        guard let cookie, !cookie.isEmpty else {
            throw YTMError.invalidHeaders("no Cookie header found")
        }
        let creds = Credentials(cookie: cookie, authUser: authUser)
        guard creds.sapisid != nil else {
            throw YTMError.invalidHeaders(
                "Cookie header has no SAPISID; make sure you are signed in and copied the request headers "
                    + "of a music.youtube.com request")
        }
        return creds
    }
}

enum SAPISIDHash {
    static let origin = "https://music.youtube.com"

    /// `SAPISIDHASH <unix-seconds>_<sha1(unix-seconds + " " + sapisid + " " + origin)>`
    static func authorization(sapisid: String, now: Date = Date()) -> String {
        let timestamp = String(Int(now.timeIntervalSince1970))
        return "SAPISIDHASH " + timestamp + "_" + sha1Hex(timestamp + " " + sapisid + " " + origin)
    }

    static func sha1Hex(_ string: String) -> String {
        Insecure.SHA1.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
