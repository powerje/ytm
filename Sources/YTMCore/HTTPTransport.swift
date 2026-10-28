import Foundation

/// The single seam between the InnerTube client and the network.
///
/// Production code uses `URLSessionTransport`. Tests supply a fake that returns
/// recorded responses, so no mocking framework is needed.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        // Ephemeral: nothing is written to disk by URLSession, and the system
        // cookie jar is never consulted or populated. The Cookie header is set
        // explicitly on each request by the client.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw YTMError.transport("Non-HTTP response")
        }
        return (data, http)
    }
}
