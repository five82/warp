import Foundation
import Observation
import os

/// The server clock, reconstructed locally: the `now` from the last lineup
/// fetch plus monotonic elapsed time. Wall clock is deliberately not used - a
/// user or NTP nudging the device's clock must not move the schedule.
struct ServerClock: Equatable {
    let serverNow: Date
    /// ProcessInfo.systemUptime when `serverNow` was captured.
    let capturedUptime: Double

    func now(uptime: Double) -> Date {
        serverNow.addingTimeInterval(uptime - capturedUptime)
    }
}

/// What the tuner should do about the program that ought to be on air.
enum TunerAction: Equatable {
    /// mpv is already on the right program; leave it alone.
    case idle
    /// Load this program at the computed offset.
    case tune(Program)
    /// This device can not decode it; show the unplayable card instead.
    case blocked(Program, reason: String)
    /// The schedule has no block covering now.
    case offAir
}

/// The tuner's decisions, kept pure so the tests can drive them without mpv,
/// a network, or a clock.
enum TunerLogic {
    /// `playingProgramId` is what mpv actually has open (learned from its
    /// `path` at playback-restart), not what we last asked for - that is what
    /// makes a block boundary self-correcting: if mpv advanced into a queued
    /// program the schedule has since changed out from under, the ids differ
    /// and the answer is a re-tune.
    static func action(
        expected: Program?,
        playingProgramId: Int64?,
        blockedProgramId: Int64?,
        blockReason: (Program) -> String?
    ) -> TunerAction {
        guard let expected else { return .offAir }
        if expected.id == playingProgramId { return .idle }
        // Already parked on this program's unplayable card; re-deciding it
        // every tick would restart the card for no reason.
        if expected.id == blockedProgramId { return .idle }
        if let reason = blockReason(expected) { return .blocked(expected, reason: reason) }
        return .tune(expected)
    }
}

/// Holds the lineup, keeps the synced clock, and drives the player.
///
/// Everything a channel flip needs is already in memory, so a flip is one mpv
/// command and no Loom round trip.
@Observable
@MainActor
final class Tuner {
    static let lastChannelKey = "tuner.lastChannel"
    /// How often the lineup is refreshed. A refresh never interrupts playback:
    /// program ids are stable, so the tuner's decision comes back .idle.
    static let refreshInterval: Duration = .seconds(600)
    /// The boundary re-check. mpv crosses program boundaries by itself through
    /// the playlist; this catches the case where the queued program is no
    /// longer the one the schedule says should be on.
    static let tickInterval: Duration = .seconds(2)

    private static let log = Logger(subsystem: "xyz.five82.warp", category: "tuner")

    private(set) var lineup: Lineup?
    private(set) var clock: ServerClock?
    private(set) var channelNumber: Int
    private(set) var current: Program?
    private(set) var next: Program?
    /// Set when the current program can not play on this device.
    private(set) var blockedReason: String?
    /// Set when the lineup can not be fetched at all.
    private(set) var loadError: String?
    private(set) var offAir = false
    /// Bumped whenever the tuner lands on a different program or channel, so
    /// the banner can show itself.
    private(set) var tuneTick = 0
    private(set) var lastTuneMilliseconds: Double?

    /// `-freeze`: pins the displayed clock so screenshots are reproducible.
    let frozen: Bool
    private var frozenNow: Date?

    private let client: LoomClient
    private let defaults: UserDefaults
    weak var controller: MPVPlayerController?

    /// What mpv actually has open, and what it has queued behind it.
    private var playingProgramId: Int64?
    private var queuedProgramId: Int64?
    private var blockedProgramId: Int64?
    private var programIdForPath: [String: Int64] = [:]

    init(client: LoomClient, defaults: UserDefaults = .standard, frozen: Bool = false, startChannel: Int? = nil) {
        self.client = client
        self.defaults = defaults
        self.frozen = frozen
        let saved = defaults.object(forKey: Self.lastChannelKey) as? Int
        channelNumber = startChannel ?? saved ?? 1
    }

    var channel: Channel? { lineup?.channel(number: channelNumber) }

    var serverNow: Date {
        if let frozenNow { return frozenNow }
        guard let clock else { return Date() }
        return clock.now(uptime: ProcessInfo.processInfo.systemUptime)
    }

    // MARK: - Player wiring

    func attach(_ controller: MPVPlayerController) {
        self.controller = controller
        controller.onPlaybackRestart = { [weak self] path, milliseconds in
            guard let self else { return }
            lastTuneMilliseconds = milliseconds
            if let path, let id = programIdForPath[path], id != playingProgramId {
                playingProgramId = id
                // mpv crossed a boundary on its own; re-decide so the queue is
                // refilled and a stale queued program is corrected.
                evaluate()
            }
        }
        controller.onEndFile = { [weak self] reason, _ in
            guard let self, reason == "eof" || reason == "error" else { return }
            // The queued entry (if any) becomes current; playback-restart will
            // confirm which. Forget the queue so evaluate() refills it.
            queuedProgramId = nil
        }
        controller.onError = { message in
            Self.log.error("\(message, privacy: .public)")
        }
    }

    // MARK: - Lifecycle

    /// Fetch the lineup, then keep it fresh. Never interrupts playback.
    func run() async {
        await refresh()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    guard let self, !Task.isCancelled else { return }
                    await refresh()
                }
            }
            group.addTask { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.tickInterval)
                    guard let self, !Task.isCancelled else { return }
                    evaluate()
                }
            }
        }
    }

    func refresh() async {
        do {
            let fetched = try await client.channels(hours: 24)
            lineup = fetched
            clock = ServerClock(serverNow: fetched.now, capturedUptime: ProcessInfo.processInfo.systemUptime)
            if frozen, frozenNow == nil { frozenNow = fetched.now }
            loadError = nil
            // A channel that vanished from the lineup falls back to the first.
            if lineup?.channel(number: channelNumber) == nil, let first = lineup?.numbers.first {
                channelNumber = first
            }
            evaluate()
        } catch {
            // Keep playing on a stale lineup; only a cold start is an error.
            if lineup == nil { loadError = error.localizedDescription }
            Self.log.error("lineup refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Channel selection

    func channelUp() { step(by: 1) }
    func channelDown() { step(by: -1) }

    private func step(by delta: Int) {
        guard let number = lineup?.number(from: channelNumber, steppingBy: delta) else { return }
        tune(to: number)
    }

    func tune(to number: Int) {
        guard number != channelNumber || playingProgramId == nil else {
            evaluate()
            return
        }
        channelNumber = number
        defaults.set(number, forKey: Self.lastChannelKey)
        // Force a load: nothing mpv holds belongs to this channel.
        playingProgramId = nil
        queuedProgramId = nil
        blockedProgramId = nil
        blockedReason = nil
        evaluate()
    }

    // MARK: - The decision

    func evaluate() {
        guard let channel else {
            if lineup != nil { offAir = true }
            return
        }
        let moment = serverNow
        let expected = channel.program(at: moment)
        let action = TunerLogic.action(
            expected: expected,
            playingProgramId: playingProgramId,
            blockedProgramId: blockedProgramId,
            blockReason: { PlaybackGate.blockReason(for: $0.video) }
        )

        switch action {
        case .offAir:
            offAir = true
            current = nil
            next = nil
        case .idle:
            offAir = false
            updateNowNext(channel: channel, at: moment)
            maintainQueue(channel: channel)
        case .blocked(let program, let reason):
            offAir = false
            blockedProgramId = program.id
            blockedReason = reason
            playingProgramId = nil
            queuedProgramId = nil
            controller?.stop()
            updateNowNext(channel: channel, at: moment)
            tuneTick += 1
        case .tune(let program):
            offAir = false
            blockedProgramId = nil
            blockedReason = nil
            load(program, at: moment, on: channel)
            updateNowNext(channel: channel, at: moment)
            tuneTick += 1
        }
    }

    private func updateNowNext(channel: Channel, at moment: Date) {
        current = channel.program(at: moment)
        next = current.flatMap { channel.program(after: $0) }
    }

    private func load(_ program: Program, at moment: Date, on channel: Channel) {
        guard let path = program.streamUrl, let url = client.streamURL(path) else {
            // Loom omits stream_url when the file has gone missing; treat it
            // like the unplayable card rather than a hard error.
            blockedProgramId = program.id
            blockedReason = "This program's file is missing on the server."
            controller?.stop()
            return
        }
        programIdForPath[url.absoluteString] = program.id
        playingProgramId = program.id
        controller?.tune(url: url, startSeconds: program.offset(at: moment))
        // loadfile replace swaps the current entry but leaves anything already
        // appended behind it; clear before re-queuing so a flip can not inherit
        // the previous channel's next program.
        queuedProgramId = nil
        controller?.clearQueue()
        maintainQueue(channel: channel)
    }

    /// Keeps mpv's playlist holding exactly the channel's next program, so
    /// prefetch-playlist can open it while the current one drains.
    private func maintainQueue(channel: Channel) {
        guard let playingProgramId,
              let playing = channel.programs.first(where: { $0.id == playingProgramId }),
              let following = channel.program(after: playing)
        else { return }
        guard following.id != queuedProgramId else { return }
        guard let path = following.streamUrl, let url = client.streamURL(path) else { return }
        programIdForPath[url.absoluteString] = following.id
        if queuedProgramId != nil { controller?.clearQueue() }
        controller?.queueNext(url: url)
        queuedProgramId = following.id
    }

    // MARK: - Debug

    /// `-surf <n>`: flip channels every 8 seconds, n times, logging each. The
    /// XCUIRemote driver only reaches the simulator, so this is how an
    /// unattended latency run happens on the physical box.
    func surf(_ count: Int) async {
        for index in 0..<count {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            channelUp()
            let line = "warp.surf \(index + 1)/\(count) -> channel \(channelNumber) \(current?.item.title ?? "-")"
            Self.log.info("\(line, privacy: .public)")
            print(line)
        }
    }
}
