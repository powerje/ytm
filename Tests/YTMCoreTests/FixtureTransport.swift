import Foundation
import Testing

@testable import YTMCore

/// Serves recorded InnerTube responses keyed by endpoint, recording what was sent.
final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: [Data]] = [:]
    private(set) var requests: [URLRequest] = []

    init() {}

    func serve(_ endpoint: String, fixture: String) throws {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"))
        lock.withLock { responses[endpoint, default: []].append(try! Data(contentsOf: url)) }
    }

    func serve(_ endpoint: String, data: Data) {
        lock.withLock { responses[endpoint, default: []].append(data) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let endpoint = request.url!.lastPathComponent
        return lock.withLock {
            requests.append(request)
            guard var queue = responses[endpoint], !queue.isEmpty else {
                return (
                    Data("{}".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                )
            }
            let data = queue.removeFirst()
            if queue.isEmpty { responses[endpoint] = nil } else { responses[endpoint] = queue }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    func lastBody() throws -> [String: Any] {
        let body = try #require(lock.withLock { requests.last?.httpBody })
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}
