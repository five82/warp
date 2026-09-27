import SwiftUI
import UIKit

/// In-memory image store over the shared URLCache. AsyncImage refetches on
/// every cell recycle; grids scroll through the same posters constantly, so
/// decoded images are worth keeping.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        // Capped by memory footprint, not count: a decoded 1440-wide backdrop
        // weighs ~5MB against a 240 bucket's ~130KB, so a count limit either
        // starves posters or lets backdrops balloon memory (the Apple TV
        // jetsams long before 600 backdrops).
        cache.totalCostLimit = 256 * 1024 * 1024
    }

    func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        // Detached so the decode happens off the main thread: UIImage(data:)
        // defers the actual JPEG decode to first render, which would land on
        // the main thread mid-scroll exactly as new cells appear.
        // byPreparingForDisplay forces it here instead.
        let session = session
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, _) = try? await session.data(from: url),
                  let image = UIImage(data: data)
            else { return nil }
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * 4 * image.scale * image.scale)
            cache.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }
}

/// Drop-in artwork view: cached, fades in on first decode, reports the
/// decoded image up (the logo lane needs its aspect ratio).
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var store: ImageStore? = nil
    var onLoad: ((UIImage) -> Void)? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            let store = store ?? ImageStore.shared
            guard let url else {
                image = nil
                return
            }
            if let hit = store.cached(for: url) {
                // Cached artwork paints on the first frame, no fade.
                image = hit
                onLoad?(hit)
                return
            }
            guard let fetched = await store.image(for: url) else { return }
            withAnimation(.easeIn(duration: 0.2)) { image = fetched }
            onLoad?(fetched)
        }
    }
}

extension CachedImage where Placeholder == Color {
    init(url: URL?, contentMode: ContentMode = .fill, store: ImageStore? = nil, onLoad: ((UIImage) -> Void)? = nil) {
        self.init(url: url, contentMode: contentMode, store: store, onLoad: onLoad) { Color.surface1 }
    }
}
