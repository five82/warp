import SwiftUI
import Testing
@testable import Warp

@MainActor
@Suite(.serialized) struct TunerViewTests {
    private func mount(_ view: TunerView) throws -> (UIWindow, UIView) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let host = UIHostingController(rootView: view.environment(AppEnvironment()))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return (window, host.view)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<50 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }

    @Test func guideAndBlockedCardRenderAfterFetch() async throws {
        let server = StubLoomServer { _ in
            (200, lineupData(channels: [
                channelJSON(number: 1, programs: [programJSON(id: 1)]),
                channelJSON(number: 2, programs: [programJSON(id: 2, stream: nil)])
            ]))
        }
        let tuner = Tuner(client: server.client, frozen: true, startChannel: 2)
        let (window, rendered) = try mount(TunerView(
            client: server.client,
            options: LaunchOptions(channel: 2, guideOpen: true, frozenClock: true),
            tuner: tuner, openSettings: {}
        ))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitFor { tuner.blockedReason != nil }
        rendered.layoutIfNeeded()
        #expect(tuner.current?.id == 2)
        #expect(tuner.blockedReason == "This program's file is missing on the server.")
        #expect(rendered.bounds.size == window.bounds.size)
    }

    @Test func bannerRendersForBlockedChannelAndEmptyScheduleGoesOffAir() async throws {
        let server = StubLoomServer { _ in
            (200, lineupData(channels: [channelJSON(number: 1, programs: [programJSON(id: 1, stream: nil)])]))
        }
        let tuner = Tuner(client: server.client, frozen: true, startChannel: 1)
        let (window, rendered) = try mount(TunerView(
            client: server.client, options: LaunchOptions(frozenClock: true),
            tuner: tuner, openSettings: {}
        ))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitFor { tuner.current != nil }
        rendered.layoutIfNeeded()
        #expect(tuner.current?.id == 1)
        #expect(tuner.blockedReason != nil)
        #expect(!tuner.offAir)
        server.reply { _ in (200, lineupData(channels: [channelJSON(number: 1, programs: [])])) }
        await tuner.refresh()
        rendered.layoutIfNeeded()
        #expect(tuner.offAir)
        #expect(tuner.current == nil)
    }

    @Test func coldFailureRendersRetryState() async throws {
        let server = StubLoomServer { _ in (503, Data()) }
        let tuner = Tuner(client: server.client, frozen: true, startChannel: 1)
        let (window, rendered) = try mount(TunerView(
            client: server.client, options: LaunchOptions(), tuner: tuner, openSettings: {}
        ))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitFor { tuner.loadError != nil }
        rendered.layoutIfNeeded()
        #expect(tuner.lineup == nil)
        #expect(tuner.loadError != nil)
        #expect(rendered.bounds.size == window.bounds.size)
    }
}
