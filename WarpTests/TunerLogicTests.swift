import Foundation
import Testing
@testable import Warp

@Suite struct ServerClockTests {
    /// The offset into a program comes from the server's clock plus monotonic
    /// elapsed time, never the device's wall clock.
    @Test func advancesWithMonotonicTime() {
        let serverNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let clock = ServerClock(serverNow: serverNow, capturedUptime: 500)
        #expect(clock.now(uptime: 500) == serverNow)
        #expect(clock.now(uptime: 530) == serverNow.addingTimeInterval(30))
        // A fetch that arrives while the box was asleep still lands correctly.
        #expect(clock.now(uptime: 3_500) == serverNow.addingTimeInterval(3_000))
    }

    /// A server clock behind the device's still drives the schedule.
    @Test func serverClockWinsOverTheDeviceClock() {
        let serverNow = Date(timeIntervalSinceReferenceDate: 0)
        let clock = ServerClock(serverNow: serverNow, capturedUptime: 100)
        let start = Date(timeIntervalSinceReferenceDate: -600)
        let program = makeProgram(id: 1, start: start, minutes: 30)
        // 10 minutes of program elapsed at capture, 15 by uptime 400.
        #expect(program.offset(at: clock.now(uptime: 100)) == 600)
        #expect(program.offset(at: clock.now(uptime: 400)) == 900)
    }
}

@Suite struct ProgramLookupTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func findsWhatIsOnAtAMoment() {
        let channel = makeChannel(from: start, blocks: 4, minutes: 30)
        #expect(channel.program(at: start)?.id == 100)
        #expect(channel.program(at: start.addingTimeInterval(29 * 60))?.id == 100)
        // Blocks are back to back: ends_at belongs to the next program.
        #expect(channel.program(at: start.addingTimeInterval(30 * 60))?.id == 101)
        #expect(channel.program(at: start.addingTimeInterval(95 * 60))?.id == 103)
    }

    @Test func returnsNothingOutsideTheSchedule() {
        let channel = makeChannel(from: start, blocks: 2, minutes: 30)
        #expect(channel.program(at: start.addingTimeInterval(-1)) == nil)
        #expect(channel.program(at: start.addingTimeInterval(60 * 60)) == nil)
    }

    @Test func offsetIntoAProgramIsClamped() {
        let program = makeProgram(id: 1, start: start, minutes: 30)
        #expect(program.offset(at: start) == 0)
        #expect(program.offset(at: start.addingTimeInterval(754)) == 754)
        // Before the block starts, land at the top rather than seeking
        // negative; past the end, at the end.
        #expect(program.offset(at: start.addingTimeInterval(-500)) == 0)
        #expect(program.offset(at: start.addingTimeInterval(10_000)) == 1800)
    }

    @Test func nextProgramFollowsTheSchedule() {
        let channel = makeChannel(from: start, blocks: 3, minutes: 30)
        let first = channel.programs[0]
        #expect(channel.program(after: first)?.id == 101)
        #expect(channel.program(after: channel.programs[2]) == nil)
    }

    @Test func blockFractionTracksProgress() {
        let program = makeProgram(id: 1, start: start, minutes: 30)
        #expect(blockFraction(program, at: start) == 0)
        #expect(blockFraction(program, at: start.addingTimeInterval(900)) == 0.5)
        #expect(blockFraction(program, at: start.addingTimeInterval(9_000)) == 1)
    }
}

@Suite struct ChannelWrapTests {
    /// Channel numbers are not dense - Loom never renumbers - so stepping
    /// walks the sorted list.
    let numbers = [1, 2, 3, 5, 8]

    @Test func stepsAndWraps() {
        #expect(Lineup.number(from: 1, steppingBy: 1, in: numbers) == 2)
        #expect(Lineup.number(from: 3, steppingBy: 1, in: numbers) == 5)
        #expect(Lineup.number(from: 8, steppingBy: 1, in: numbers) == 1)
        #expect(Lineup.number(from: 1, steppingBy: -1, in: numbers) == 8)
        #expect(Lineup.number(from: 5, steppingBy: -1, in: numbers) == 3)
    }

    @Test func aVanishedChannelStepsFromWhereItSat() {
        // 4 is gone from the lineup; up from it lands on 5's successor's
        // neighbourhood rather than resetting to the top.
        #expect(Lineup.number(from: 4, steppingBy: 1, in: numbers) == 8)
        #expect(Lineup.number(from: 4, steppingBy: 0, in: numbers) == 5)
    }

    @Test func anEmptyLineupHasNowhereToGo() {
        #expect(Lineup.number(from: 1, steppingBy: 1, in: []) == nil)
    }

    @Test func aSingleChannelWrapsToItself() {
        #expect(Lineup.number(from: 7, steppingBy: 1, in: [7]) == 7)
        #expect(Lineup.number(from: 7, steppingBy: -1, in: [7]) == 7)
    }
}

@Suite struct BoundaryDecisionTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let playable: (Program) -> String? = { _ in nil }

    @Test func leavesMpvAloneWhenItIsAlreadyRight() {
        let program = makeProgram(id: 100, start: start, minutes: 30)
        let action = TunerLogic.action(
            expected: program, playingProgramId: 100, blockedProgramId: nil, blockReason: playable
        )
        #expect(action == .idle)
    }

    /// The boundary case that matters: mpv advanced into the program the
    /// client queued, and the schedule agrees. No re-tune.
    @Test func acceptsAQueuedProgramMpvAdvancedInto() {
        let channel = makeChannel(from: start, blocks: 3, minutes: 30)
        let atBoundary = start.addingTimeInterval(30 * 60)
        let expected = channel.program(at: atBoundary)
        let action = TunerLogic.action(
            expected: expected, playingProgramId: 101, blockedProgramId: nil, blockReason: playable
        )
        #expect(action == .idle)
    }

    /// The schedule was regenerated behind us: mpv is playing the old queued
    /// program, so the boundary has to re-tune.
    @Test func reTunesWhenTheQueuedProgramIsNoLongerScheduled() throws {
        let channel = makeChannel(from: start, blocks: 3, minutes: 30, firstProgramId: 200)
        let atBoundary = start.addingTimeInterval(30 * 60)
        let expected = try #require(channel.program(at: atBoundary))
        let action = TunerLogic.action(
            expected: expected, playingProgramId: 101, blockedProgramId: nil, blockReason: playable
        )
        #expect(action == .tune(expected))
    }

    @Test func offAirWhenTheScheduleHasAHole() {
        let action = TunerLogic.action(
            expected: nil, playingProgramId: 100, blockedProgramId: nil, blockReason: playable
        )
        #expect(action == .offAir)
    }

    @Test func blocksWhatThisBoxCanNotDecode() {
        let program = makeProgram(
            id: 100, start: start, minutes: 120,
            video: VideoSummary(codec: "av1", width: 3840, height: 2160, resolution: "4k", dynamicRange: "hdr")
        )
        let action = TunerLogic.action(
            expected: program, playingProgramId: nil, blockedProgramId: nil,
            blockReason: { PlaybackGate.blockReason(codec: $0.video?.codec, width: $0.video?.width, height: $0.video?.height, av1HardwareDecode: false) }
        )
        #expect(action == .blocked(program, reason: "This Apple TV can not play 4K AV1 video smoothly."))
    }

    /// Once the card is up, the tuner stays put instead of re-deciding the
    /// same blocked program every tick.
    @Test func staysOnTheUnplayableCardUntilTheNextBlock() {
        let program = makeProgram(id: 100, start: start, minutes: 120)
        let action = TunerLogic.action(
            expected: program, playingProgramId: nil, blockedProgramId: 100, blockReason: playable
        )
        #expect(action == .idle)
        // The next block is playable and takes over on its own.
        let following = makeProgram(id: 101, start: start.addingTimeInterval(7200), minutes: 30)
        let next = TunerLogic.action(
            expected: following, playingProgramId: nil, blockedProgramId: 100, blockReason: playable
        )
        #expect(next == .tune(following))
    }
}
