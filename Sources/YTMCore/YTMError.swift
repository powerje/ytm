import Foundation

public enum YTMError: Error, CustomStringConvertible, Sendable {
    case notLoggedIn
    case sessionExpired
    case sessionRejected
    case invalidHeaders(String)
    case transport(String)
    case httpStatus(Int)
    case unexpectedResponse(String)
    case io(String)

    public var description: String {
        switch self {
        case .notLoggedIn:
            return "Not logged in. Run `ytm login` first."
        case .sessionExpired:
            return "Your YouTube Music session has expired. Run `ytm login` again."
        case .sessionRejected:
            return "YouTube Music did not treat the request as signed in. Make sure the whole curl command was pasted "
                + "(cookies are often cut off by the terminal; `pbpaste | ytm login` avoids that) and that you are "
                + "signed in in the browser."
        case .invalidHeaders(let why):
            return "Could not use the pasted headers: \(why)"
        case .transport(let why):
            return "Network error: \(why)"
        case .httpStatus(let code):
            return "YouTube Music returned HTTP \(code)"
        case .unexpectedResponse(let why):
            return "Unexpected response from YouTube Music: \(why)"
        case .io(let why):
            return why
        }
    }
}
