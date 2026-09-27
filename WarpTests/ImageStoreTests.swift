import SwiftUI
import Testing
@testable import Warp

@MainActor
@Suite(.serialized) struct ImageStoreTests {
    @Test func fetchedArtworkIsCachedAndReused() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let png = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let lock = NSLock()
        var requests = 0
        let server = StubLoomServer { _ in
            lock.withLock { requests += 1 }
            return (200, png)
        }
        let store = ImageStore(session: server.session)
        let url = server.baseURL.appending(path: "poster.png")

        #expect(store.cached(for: url) == nil)
        let fetched = await store.image(for: url)
        #expect(fetched?.size == UIImage(data: png)?.size)
        #expect(store.cached(for: url) === fetched)
        #expect(await store.image(for: url) === fetched)
        #expect(lock.withLock { requests } == 1)
    }

    @Test func invalidArtworkDoesNotPoisonLaterAttempts() async {
        let server = StubLoomServer { _ in (200, Data("not an image".utf8)) }
        let store = ImageStore(session: server.session)
        let url = server.baseURL.appending(path: "bad.png")
        #expect(await store.image(for: url) == nil)
        #expect(store.cached(for: url) == nil)
        #expect(await store.image(for: url) == nil)
    }
}
