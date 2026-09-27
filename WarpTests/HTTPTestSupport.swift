import Foundation
@testable import Warp

/// Intercepts only requests for this test's unique host; no LAN or Loom process needed.
private final class StubURLProtocol: URLProtocol {
    typealias Reply = (Int, Data)
    private static let lock = NSLock()
    private static var replies: [String: (URLRequest) -> Reply] = [:]

    static func set(_ handler: @escaping (URLRequest) -> Reply, for host: String) {
        lock.lock()
        replies[host] = handler
        lock.unlock()
    }

    static func remove(host: String) {
        lock.lock()
        replies.removeValue(forKey: host)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return replies[request.url?.host ?? ""] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.replies[request.url?.host ?? ""]
        Self.lock.unlock()
        guard let handler, let url = request.url else { return }
        let (status, data) = handler(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class StubLoomServer {
    let baseURL: URL
    let client: LoomClient
    private let session: URLSession

    init(_ handler: @escaping (URLRequest) -> (Int, Data)) {
        let host = "stub-\(UUID().uuidString.lowercased()).test"
        baseURL = URL(string: "http://\(host):8097/")!
        StubURLProtocol.set(handler, for: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        client = LoomClient(baseURL: baseURL, session: session)
    }

    func reply(_ handler: @escaping (URLRequest) -> (Int, Data)) {
        StubURLProtocol.set(handler, for: baseURL.host!)
    }

    deinit {
        session.invalidateAndCancel()
        StubURLProtocol.remove(host: baseURL.host!)
    }
}

func jsonData(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

func lineupData(now: String = "2025-01-01T12:15:00Z", channels: [[String: Any]]) -> Data {
    jsonData(["now": now, "items": channels])
}

func channelJSON(number: Int, programs: [[String: Any]]) -> [String: Any] {
    ["id": number, "number": number, "key": "show:\(number)", "name": "Channel \(number)", "programs": programs]
}

func programJSON(id: Int, start: String = "2025-01-01T12:00:00Z", end: String = "2025-01-01T12:30:00Z", stream: String? = "/api/v1/media/1", video: [String: Any]? = nil) -> [String: Any] {
    var result: [String: Any] = ["id": id, "starts_at": start, "ends_at": end, "item": ["id": id, "kind": "episode", "title": "Program \(id)"]]
    if let stream { result["stream_url"] = stream }
    if let video { result["video"] = video }
    return result
}
