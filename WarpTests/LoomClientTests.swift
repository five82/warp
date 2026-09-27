import Foundation
import Testing
@testable import Warp

@Suite struct LoomClientTests {
    @Test func healthAcceptsEmptyResponseAndUsesExpectedPath() async throws {
        let server = StubLoomServer { request in
            #expect(request.url?.path == "/api/v1/health")
            #expect(request.httpMethod == "GET")
            return (204, Data())
        }
        try await server.client.health()
    }

    @Test func listsDecodeSnakeCaseAndNullItems() async throws {
        let server = StubLoomServer { request in
            #expect(request.url?.path == "/api/v1/libraries")
            return (200, jsonData(["items": [["id": 3, "kind": "show", "name": "Series", "item_count": 42]]]))
        }
        let libraries = try await server.client.libraries()
        #expect(libraries.count == 1)
        #expect(libraries.first?.itemCount == 42)
        server.reply { _ in (200, jsonData(["items": NSNull()])) }
        #expect(try await server.client.libraries().isEmpty)
    }

    @Test func channelRequestIncludesHorizonAndDecodesSchedule() async throws {
        let server = StubLoomServer { request in
            #expect(request.url?.path == "/api/v1/channels")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "hours", value: "12")])
            return (200, lineupData(channels: [channelJSON(number: 7, programs: [programJSON(id: 70)])]))
        }
        let lineup = try await server.client.channels(hours: 12)
        #expect(lineup.numbers == [7])
        #expect(lineup.channel(number: 7)?.programs.first?.id == 70)
    }

    @Test func httpErrorsPreferServerMessageAndFallbackToStatus() async {
        let server = StubLoomServer { _ in (503, jsonData(["error": "Loom is unavailable"])) }
        do {
            try await server.client.health()
            Issue.record("Expected HTTP error")
        } catch let error as LoomError {
            #expect(error.statusCode == 503)
            #expect(error.errorDescription == "Loom is unavailable")
        } catch { Issue.record("Unexpected error: \(error)") }

        server.reply { _ in (404, Data("not JSON".utf8)) }
        do {
            _ = try await server.client.channels()
            Issue.record("Expected HTTP error")
        } catch let error as LoomError {
            #expect(error.statusCode == 404)
            #expect(error.errorDescription == "Loom request failed (HTTP 404)")
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func invalidJSONIsNotSilentlyAccepted() async {
        let server = StubLoomServer { _ in (200, Data("broken".utf8)) }
        await #expect(throws: DecodingError.self) { try await server.client.libraries() }
    }

    @Test func mediaAndArtworkURLsStayOnSelectedServer() {
        let client = LoomClient(baseURL: URL(string: "http://loom.local:8097/")!)
        #expect(client.streamURL("/api/v1/media/10?tag=one")?.absoluteString == "http://loom.local:8097/api/v1/media/10?tag=one")
        #expect(client.imageURL(id: nil, tag: nil, width: 240) == nil)
        #expect(client.imageURL(id: 0, tag: nil, width: 240) == nil)
        let image = client.imageURL(id: 44, tag: "a&b", width: 480)
        #expect(image?.path == "/api/v1/images/44")
        #expect(URLComponents(url: image!, resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "width", value: "480"), URLQueryItem(name: "tag", value: "a&b")
        ])
        #expect(client.imageURL(id: 44, tag: nil, width: 240)?.query == "width=240")
    }
}
