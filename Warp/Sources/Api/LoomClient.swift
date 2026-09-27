import Foundation

struct LoomError: Error, LocalizedError {
    let statusCode: Int
    let serverMessage: String?

    var errorDescription: String? {
        serverMessage ?? "Loom request failed (HTTP \(statusCode))"
    }
}

/// Thin client for Loom's /api/v1, trimmed from Takeup's to what Warp needs:
/// a health probe for onboarding, the library list, and the channel lineup.
struct LoomClient {
    let baseURL: URL

    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// A per-client session lets tests stub HTTP without contacting a Loom server.
    let session: URLSession

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.session = session ?? Self.defaultSession
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - Endpoints

    func health() async throws {
        let _: EmptyResponse = try await request("health")
    }

    // List endpoints wrap their arrays in {"items": [...]}; an empty list
    // arrives as {"items": null} (Go marshals nil slices as null).
    private struct Wrapped<Element: Decodable>: Decodable {
        let items: [Element]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([Element].self, forKey: .items) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case items
        }
    }

    func libraries() async throws -> [Library] {
        let wrapped: Wrapped<Library> = try await request("libraries")
        return wrapped.items
    }

    /// The whole lineup in one response: every channel's schedule through the
    /// horizon plus the server clock. Warp holds it in memory so a channel flip
    /// costs no network round trip at all.
    func channels(hours: Int = 24) async throws -> Lineup {
        try await request("channels", query: [URLQueryItem(name: "hours", value: String(hours))])
    }

    // MARK: - URLs

    /// A program's `stream_url` (a server-relative path) against this server.
    func streamURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Server-resized artwork. Width snaps up to Loom's buckets: 240/480/960/1440.
    func imageURL(id: Int64?, tag: String?, width: Int) -> URL? {
        guard let id, id != 0 else { return nil }
        var components = URLComponents(url: baseURL.appending(path: "api/v1/images/\(id)"), resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "width", value: String(width))]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        components?.queryItems = query
        return components?.url
    }

    // MARK: - Plumbing

    private struct EmptyResponse: Decodable {}
    private struct ServerError: Decodable { let error: String? }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/\(path)"), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = try? Self.decoder.decode(ServerError.self, from: data).error
            throw LoomError(statusCode: status, serverMessage: message ?? nil)
        }
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
