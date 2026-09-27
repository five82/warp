import Foundation
import Testing
@testable import Warp

@MainActor
@Suite struct TunerIntegrationTests {
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        return defaults
    }

    @Test func refreshLoadsLineupAndUsesServerClockNotDeviceTime() async {
        let server = StubLoomServer { _ in
            (200, lineupData(channels: [channelJSON(number: 4, programs: [programJSON(id: 40)])]))
        }
        let tuner = Tuner(client: server.client, defaults: defaults(), frozen: true, startChannel: 19)
        await tuner.refresh()
        #expect(tuner.channelNumber == 4) // saved channel disappeared
        #expect(tuner.current?.id == 40)
        #expect(tuner.serverNow == tuner.lineup?.now)
        #expect(tuner.next == nil)
        #expect(tuner.tuneTick == 1)
        #expect(tuner.loadError == nil)
        tuner.evaluate()
        #expect(tuner.tuneTick == 1) // no unnecessary retune
    }

    @Test func channelFlipsWrapAndPersistWithoutARequest() async {
        let data = lineupData(channels: [
            channelJSON(number: 2, programs: [programJSON(id: 20)]),
            channelJSON(number: 9, programs: [programJSON(id: 90)])
        ])
        let server = StubLoomServer { _ in (200, data) }
        let preferences = defaults()
        let tuner = Tuner(client: server.client, defaults: preferences, frozen: true, startChannel: 2)
        await tuner.refresh()
        tuner.channelUp()
        #expect(tuner.channelNumber == 9)
        #expect(tuner.current?.id == 90)
        #expect(preferences.integer(forKey: Tuner.lastChannelKey) == 9)
        tuner.channelUp()
        #expect(tuner.channelNumber == 2)
        tuner.channelDown()
        #expect(tuner.channelNumber == 9)
        tuner.tune(to: 9)
        #expect(tuner.current?.id == 90)
        #expect(tuner.loadError == nil)
    }

    @Test func missingStreamShowsCardUntilNextBlockAndScheduleHoleIsOffAir() async {
        let missing = programJSON(id: 1, stream: nil)
        let data = lineupData(channels: [channelJSON(number: 1, programs: [missing])])
        let server = StubLoomServer { _ in (200, data) }
        let tuner = Tuner(client: server.client, defaults: defaults(), frozen: true)
        await tuner.refresh()
        #expect(tuner.current?.id == 1)
        #expect(tuner.blockedReason == "This program's file is missing on the server.")
        let tick = tuner.tuneTick
        tuner.evaluate()
        #expect(tuner.tuneTick == tick)
        tuner.suspend()
        #expect(tuner.current?.id == 1)
        // On resume a new lineup without a block for server-now goes off air.
        server.reply { _ in (200, lineupData(channels: [channelJSON(number: 1, programs: [])])) }
        await tuner.resync()
        #expect(tuner.offAir)
        #expect(tuner.current == nil)
        #expect(tuner.next == nil)
    }

    @Test func coldFailureReportsErrorButLaterFailureKeepsPlaying() async {
        let server = StubLoomServer { _ in (503, Data()) }
        let tuner = Tuner(client: server.client, defaults: defaults(), frozen: true)
        await tuner.refresh()
        #expect(tuner.loadError != nil)
        server.reply { _ in (200, lineupData(channels: [channelJSON(number: 1, programs: [programJSON(id: 1)])])) }
        await tuner.refresh()
        #expect(tuner.current?.id == 1)
        #expect(tuner.loadError == nil)
        server.reply { _ in (503, Data()) }
        await tuner.refresh()
        #expect(tuner.current?.id == 1)
        #expect(tuner.loadError == nil)
    }

    @Test func blockedVideoClearsOnChannelChangeAndNextProgramIsTracked() async {
        let data = lineupData(channels: [
            channelJSON(number: 1, programs: [programJSON(id: 1, video: ["codec": "av1", "width": 3840, "height": 2160])]),
            channelJSON(number: 2, programs: [
                programJSON(id: 2),
                programJSON(id: 3, start: "2025-01-01T12:30:00Z", end: "2025-01-01T13:00:00Z")
            ])
        ])
        let server = StubLoomServer { _ in (200, data) }
        let tuner = Tuner(client: server.client, defaults: defaults(), frozen: true)
        await tuner.refresh()
        // Whether AV1 is blocked is device-dependent; the next channel is not.
        tuner.tune(to: 2)
        #expect(tuner.blockedReason == nil)
        #expect(tuner.current?.id == 2)
        #expect(tuner.next?.id == 3)
        #expect(!tuner.offAir)
    }
}
