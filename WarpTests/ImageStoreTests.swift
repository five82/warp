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

    @Test func concurrentRequestsShareOneDownload() async {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let png = renderer.pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let lock = NSLock()
        var requests = 0
        let server = StubLoomServer { _ in
            lock.withLock { requests += 1 }
            Thread.sleep(forTimeInterval: 0.05)
            return (200, png)
        }
        let store = ImageStore(session: server.session)
        let url = server.baseURL.appending(path: "shared.png")

        async let first = store.image(for: url)
        async let second = store.image(for: url)
        let (one, two) = await (first, second)
        #expect(one != nil)
        #expect(one === two)
        #expect(store.cached(for: url) === one)
        #expect(lock.withLock { requests } == 1)
    }

    @Test func cachedImageLoadsAndReusesArtworkWhenURLChanges() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let png = renderer.pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let lock = NSLock()
        var requests = 0
        let server = StubLoomServer { _ in
            lock.withLock { requests += 1 }
            return (200, png)
        }
        let store = ImageStore(session: server.session)
        let url = server.baseURL.appending(path: "art.png")
        var loaded: [UIImage] = []
        func artwork(_ url: URL?) -> CachedImage<Color> {
            CachedImage(url: url, store: store, onLoad: { loaded.append($0) })
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: artwork(nil))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        #expect(loaded.isEmpty)

        host.rootView = artwork(url)
        for _ in 0..<50 {
            if loaded.count == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(loaded.count == 1)
        #expect(store.cached(for: url) === loaded.first)

        host.rootView = artwork(nil)
        host.view.layoutIfNeeded()
        // Allow the nil-URL task to run before changing identity again;
        // otherwise SwiftUI can coalesce both root-view updates.
        try await Task.sleep(for: .milliseconds(50))
        host.rootView = artwork(url)
        for _ in 0..<50 {
            if loaded.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(loaded.count == 2)
        #expect(loaded.first === loaded.last)
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
