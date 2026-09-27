import SwiftUI
import Testing
@testable import Warp

@MainActor
@Suite(.serialized) struct PresentationTests {
    /// Mount rather than just constructing the View: SwiftUI evaluates conditional
    /// branches and layout closures only when hosted in a real scene.
    private func render<V: View>(_ view: V) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.layoutIfNeeded()
        #expect(host.view.bounds.size == window.bounds.size)
        #expect(host.view.window === window)
    }

    @Test func bannerWithEpisodeAndNextBlock() {
        let now = Date(timeIntervalSince1970: 1_735_733_700)
        let episode = makeItem(id: 1, title: "Pilot", season: 1, episode: 1, seriesTitle: "Example")
        let first = makeProgram(id: 1, start: now.addingTimeInterval(-600), minutes: 30,
                                item: episode, video: VideoSummary(codec: "hevc", width: 3840, height: 2160,
                                                                    resolution: "4k", dynamicRange: "hdr"))
        let second = makeProgram(id: 2, start: first.endsAt, minutes: 30,
                                 item: makeItem(id: 2, kind: "movie", title: "Up Next"))
        let channel = Channel(id: 1, number: 7, key: "show:7", name: "Seven", programs: [first, second])
        let environment = AppEnvironment()
        // Items have no artwork IDs, so no request leaves the simulator.
        render(ChannelBanner(channel: channel, program: first, next: second, now: now,
                             captionsEnabled: true).environment(environment))
        render(ChannelBanner(channel: channel, program: second, next: nil, now: second.startsAt,
                             captionsEnabled: false).environment(environment))
    }

    @Test func emptyBannerAndBlockedCards() {
        let now = Date(timeIntervalSince1970: 1_735_733_700)
        let program = makeProgram(id: 3, start: now, minutes: 30)
        let channel = Channel(id: 3, number: 3, key: "show:3", name: "Three", programs: [program])
        render(ChannelBanner(channel: channel, program: nil, next: nil, now: now, captionsEnabled: false))
        render(UnplayableCard(channel: channel, program: program, next: program, reason: "AV1 needs hardware decode"))
        render(UnplayableCard(channel: channel, program: nil, next: nil, reason: "Missing stream"))
    }

    @Test func sharedComponentsWithAndWithoutActions() {
        render(VStack {
            Glow()
            BlockProgress(fraction: -1, color: .cobalt)
            BlockProgress(fraction: 2, color: .amber)
            MissingArt(title: "Unavailable", tint: .cobalt)
            TechBadge(text: "hdr")
            ErrorState(message: "Offline", retry: {})
        })
        render(ErrorState(message: "Offline", retry: nil))
    }
}
