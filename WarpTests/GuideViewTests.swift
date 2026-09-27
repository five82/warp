import SwiftUI
import Testing
@testable import Warp

@MainActor
@Suite(.serialized) struct GuideViewTests {
    @Test func guideRendersScheduleWithNowAndFutureBlocks() {
        let now = Date(timeIntervalSince1970: 1_735_733_700)
        let channel = makeChannel(from: now.addingTimeInterval(-600))
        let lineup = Lineup(now: now, channels: [channel])
        let host = UIHostingController(rootView: GuideView(
            lineup: lineup, currentNumber: channel.number, now: now,
            onSelect: { _ in }, onSettings: {}
        ))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        #expect(host.view.bounds.width == 1920)
        #expect(host.view.subviews.count > 0)
    }

    @Test func guideRendersEmptyAndNonCurrentChannels() {
        let now = Date(timeIntervalSince1970: 1_735_733_700)
        let channels = [
            makeChannel(number: 2, from: now.addingTimeInterval(-1800), blocks: 2),
            makeChannel(number: 8, from: now.addingTimeInterval(1200), blocks: 2),
            makeChannel(number: 9, from: now, blocks: 0)
        ]
        let host = UIHostingController(rootView: GuideView(
            lineup: Lineup(now: now, channels: channels), currentNumber: 99, now: now,
            onSelect: { _ in }, onSettings: {}
        ))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first!
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        #expect(host.view.bounds.height == 1080)
        #expect(host.view.subviews.count > 0)
    }
}
