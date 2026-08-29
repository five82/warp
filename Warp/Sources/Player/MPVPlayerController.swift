import UIKit
import Libmpv
import Metal
import os

/// Hosts one long-lived libmpv instance rendering into a CAMetalLayer.
///
/// Unlike Takeup's player, this controller is created once and kept for the
/// life of the app: a channel flip is a single `loadfile ... replace` into the
/// running core, so the Vulkan device, swapchain, and the PQ layer survive it
/// (that is what `force-window=immediate` and `idle=yes` buy). Tearing mpv
/// down per program would cost hundreds of milliseconds at exactly the moment
/// the whole app is judged on.
final class MPVPlayerController: UIViewController {
    struct ObservedState {
        var timeSeconds: Double = 0
        var durationSeconds: Double = 0
        var paused: Bool = false
        var buffering: Bool = true
    }

    /// Fired on the main thread at MPV_EVENT_PLAYBACK_RESTART - the first
    /// frame after a load or a seek - with mpv's current `path` and the
    /// milliseconds since the matching `tune`. The tuner uses the path to tell
    /// whether mpv landed on the program it expected.
    var onPlaybackRestart: ((_ path: String?, _ tuneMilliseconds: Double?) -> Void)?
    /// Fired on the main thread at MPV_EVENT_FILE_LOADED with the loaded path.
    var onFileLoaded: ((_ path: String?) -> Void)?
    /// Fired on the main thread at MPV_EVENT_END_FILE with mpv's reason
    /// ("eof", "stop", "error", "redirect", "quit").
    var onEndFile: ((_ reason: String, _ errorText: String?) -> Void)?
    /// Fired on the main thread for command/option failures and mpv errors.
    var onError: ((String) -> Void)?
    /// Fired on the main thread whenever an observed property changes.
    var onStateChange: ((ObservedState) -> Void)?

    private static let log = Logger(subsystem: "xyz.five82.warp", category: "player")

    private var metalLayer = MetalLayer()
    private var mpv: OpaquePointer!
    private let eventQueue = DispatchQueue(label: "mpv.events", qos: .userInitiated)
    private var state = ObservedState()
    /// Monotonic timestamp of the last `tune`, in seconds. Read and cleared on
    /// the event queue at PLAYBACK_RESTART; written from the main thread. The
    /// race is benign: the worst case is one flip reported as untimed.
    private var tuneStartedAt: Double?
    private var loggedSurfaceFormat = false

    private static var monotonicSeconds: Double {
        // systemUptime is CLOCK_MONOTONIC and is unaffected by wall-clock
        // changes, which matters because the tuner is syncing to a server clock.
        ProcessInfo.processInfo.systemUptime
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.windowScene?.screen.nativeScale ?? 2
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        setupMpv()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        if let scale = view.window?.windowScene?.screen.nativeScale {
            metalLayer.contentsScale = scale
        }
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(
            width: view.bounds.width * scale,
            height: view.bounds.height * scale
        )
        CATransaction.commit()
    }

    private func setupMpv() {
        mpv = mpv_create()
        guard mpv != nil else {
            assertionFailure("mpv_create failed")
            return
        }

#if DEBUG
        checkError(mpv_request_log_messages(mpv, "warn"))
#else
        checkError(mpv_request_log_messages(mpv, "no"))
#endif
        // mpv takes the render target as a pointer stuffed into an int64.
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid))

        // Rendering path, carried over from Takeup.
        setOption("vo", "gpu-next")
        setOption("gpu-api", "vulkan")
        setOption("gpu-context", "moltenvk")
        setOption("hwdec", "videotoolbox")
        setOption("video-rotate", "no")

        // Pinned PQ/BT.2020 output (docs/proposal.md 2.1). Everything is
        // rendered into the same HDR container so the swapchain hint and the
        // layer colorspace never change on a flip; SDR sits in it at a fixed
        // reference white rather than being stretched.
        //
        // target-peak=auto is 10,000 nits on a PQ target, which exceeds any
        // real mastering peak, so libplacebo's tone-mapping curve collapses to
        // identity for HDR10 sources. Do NOT set the TV's real peak here.
        setOption("target-colorspace-hint", "yes")  // must be set before init
        setOption("target-trc", "pq")
        setOption("target-prim", "bt.2020")
        setOption("target-peak", "auto")
        setOption("target-contrast", "auto")
        setOption("tone-mapping", "auto")
        setOption("inverse-tone-mapping", "no")
        setOption("hdr-compute-peak", "no")
        // SDR white at 100 nits: the calibrated SDR-mode level, so an SDR
        // channel looks like the TV's own SDR picture. mpv's default of 203
        // (the BT.2408 broadcast convention) read as too bright on the house
        // TV (2026-08-29).
        setOption("hdr-reference-white", "100")

        // Keep the VO, Vulkan device, and swapchain alive across loadfile and
        // across an empty playlist. Without force-window mpv tears the VO down
        // on every load and rebuilds it (hundreds of ms), dropping the pinned
        // PQ layer at the worst possible moment.
        setOption("force-window", "immediate")
        setOption("idle", "yes")
        // Only the last playlist entry holds its final frame; entries still
        // advance normally, which is what makes program boundaries seamless.
        setOption("keep-open", "yes")

        // Channel-change latency (docs/proposal.md 2.3). A keyframe seek lands
        // a few seconds shy of "live", which is invisible on a fake channel and
        // avoids decoding a whole GOP before the first frame.
        setOption("hr-seek", "no")
        setOption("cache-pause", "no")
        setOption("video-latency-hacks", "yes")
        setOption("interpolation", "no")
        setOption("video-sync", "audio")
        // Holds the audio device open between programs so a flip never waits
        // on the audio stack to spin up.
        setOption("audio-stream-silence", "yes")
        // HTTP keep-alive: one connection reused across range requests.
        setOption("stream-lavf-o", "multiple_requests=1")
        // Opens the appended next program while the current one drains.
        setOption("prefetch-playlist", "yes")

        checkError(mpv_initialize(mpv))

        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        mpv_set_wakeup_callback(mpv, { ctx in
            let controller = unsafeBitCast(ctx, to: MPVPlayerController.self)
            controller.readEvents()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
    }

    private func setOption(_ name: String, _ value: String) {
        checkError(mpv_set_option_string(mpv, name, value), context: "\(name)=\(value)")
    }

    // MARK: - Commands

    /// Tune to a program: replace whatever is playing and land `startSeconds`
    /// in. One mpv command, no network round trip to Loom.
    func tune(url: URL, startSeconds: Double, sdr: Bool) {
        tuneStartedAt = Self.monotonicSeconds
        // mpv >= 0.38 loadfile signature: url [flags [index [options]]]. The
        // index (-1 = append position, unused for "replace") must be present or
        // the options string is rejected and nothing loads.
        let options = ["start=\(max(startSeconds, 0))"] + Self.perFileOptions(sdr: sdr)
        command("loadfile", args: [url.absoluteString, "replace", "-1", options.joined(separator: ",")])
    }

    /// Append the channel's next program so prefetch-playlist opens it while
    /// the current one drains; mpv crosses the boundary with no client work.
    func queueNext(url: URL, sdr: Bool) {
        let options = Self.perFileOptions(sdr: sdr)
        if options.isEmpty {
            command("loadfile", args: [url.absoluteString, "append"])
        } else {
            command("loadfile", args: [url.absoluteString, "append", "-1", options.joined(separator: ",")])
        }
    }

    /// Options scoped to one playlist entry (mpv reverts them when the entry
    /// ends), so a per-program choice never leaks into the next flip.
    ///
    /// SDR sources are retagged as a pure 2.2 power curve. libplacebo decodes
    /// BT.709 as BT.1886 (about 2.4 with a black lift), which is the reference
    /// EOTF but reads contrastier than the TV's own SDR mode, which runs a
    /// plain 2.2 (observed 2026-08-29). `format` with only colorimetry tags
    /// changes metadata, not pixels, so it works on VideoToolbox frames. HDR
    /// sources keep their PQ tag untouched.
    private static func perFileOptions(sdr: Bool) -> [String] {
        sdr ? ["vf=format:gamma=gamma2.2"] : []
    }

    func clearQueue() {
        command("playlist-clear")
    }

    /// Stop playback without killing the core (idle=yes keeps it warm). Used
    /// for the unplayable card.
    func stop() {
        tuneStartedAt = nil
        command("stop")
    }

    func setPaused(_ paused: Bool) {
        guard mpv != nil else { return }
        var data: Int = paused ? 1 : 0
        mpv_set_property(mpv, "pause", MPV_FORMAT_FLAG, &data)
    }

    /// Tears down mpv synchronously enough to be safe: the wakeup callback is
    /// detached first so it can never fire into a deallocated controller, then
    /// the handle is destroyed on the event queue after any in-flight drain.
    func shutdown() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        eventQueue.async {
            mpv_terminate_destroy(handle)
        }
    }

    deinit {
        shutdown()
    }

    // MARK: - Property helpers

    private func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        guard let cString = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }

    private func command(_ command: String, args: [String?] = []) {
        guard mpv != nil else { return }
        var strArgs: [String?] = [command] + args
        strArgs.append(nil)
        var cargs = strArgs.map { $0.flatMap { UnsafePointer<CChar>(strdup($0)) } }
        defer {
            for pointer in cargs where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer!))
            }
        }
        checkError(mpv_command(mpv, &cargs), context: ([command] + args.compactMap { $0 }).joined(separator: " "))
    }

    // MARK: - Events

    private func readEvents() {
        eventQueue.async { [weak self] in
            // Capture the handle once: shutdown() enqueues mpv_terminate_destroy
            // on this same serial queue, so it stays valid for the whole drain.
            guard let self, let handle = self.mpv else { return }
            while self.mpv != nil {
                guard let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE else {
                    break
                }
                switch event.pointee.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    self.handlePropertyChange(event)
                case MPV_EVENT_FILE_LOADED:
                    let path = self.getString("path")
                    DispatchQueue.main.async { [weak self] in
                        self?.onFileLoaded?(path)
                    }
                case MPV_EVENT_PLAYBACK_RESTART:
                    self.handlePlaybackRestart()
                case MPV_EVENT_END_FILE:
                    self.handleEndFile(event)
                case MPV_EVENT_SHUTDOWN:
                    if let handle = self.mpv {
                        self.mpv = nil
                        mpv_set_wakeup_callback(handle, nil, nil)
                        mpv_terminate_destroy(handle)
                    }
                case MPV_EVENT_LOG_MESSAGE:
                    if let message = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) {
                        print("[mpv \(String(cString: message.pointee.level!))] \(String(cString: message.pointee.text!))", terminator: "")
                    }
                default:
                    break
                }
            }
        }
    }

    /// First frame after a load or seek. This is the moment a channel flip is
    /// judged on, so it is where the tune latency is measured.
    private func handlePlaybackRestart() {
        let path = getString("path")
        var milliseconds: Double?
        if let started = tuneStartedAt {
            milliseconds = (Self.monotonicSeconds - started) * 1000
            tuneStartedAt = nil
        }
        if let milliseconds {
            let line = String(format: "warp.tune %.0f ms %@", milliseconds, path ?? "-")
            Self.log.info("\(line, privacy: .public)")
            // devicectl's --console captures stdout; os_log lands in the system
            // log. Both, so a measurement is never lost to the capture method.
            print(line)
        }
        if !loggedSurfaceFormat {
            loggedSurfaceFormat = true
            DispatchQueue.main.async { [weak self] in
                self?.logSurfaceFormat()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackRestart?(path, milliseconds)
        }
    }

    /// Proof that the PQ negotiation actually took: mpv sets the layer's
    /// colorspace from target-colorspace-hint, and the pixel format tells us
    /// whether we got a 10-bit surface.
    private func logSurfaceFormat() {
        let space = metalLayer.colorspace?.name as String? ?? "nil"
        let line = "warp.surface colorspace=\(space) pixelFormat=\(metalLayer.pixelFormat.rawValue) (\(Self.name(of: metalLayer.pixelFormat)))"
        Self.log.info("\(line, privacy: .public)")
        print(line)
    }

    private static func name(of format: MTLPixelFormat) -> String {
        switch format {
        case .bgra8Unorm: "bgra8Unorm"
        case .bgra8Unorm_srgb: "bgra8Unorm_srgb"
        case .rgba16Float: "rgba16Float"
        // The two 10-bit formats a PQ swapchain lands on.
        case .rgb10a2Unorm: "rgb10a2Unorm"
        case .bgr10a2Unorm: "bgr10a2Unorm"
        case .bgra10_xr: "bgra10_xr"
        case .bgra10_xr_srgb: "bgra10_xr_srgb"
        default: "other"
        }
    }

    private func handleEndFile(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let end = UnsafePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data))?.pointee else { return }
        let reason: String
        switch end.reason {
        case MPV_END_FILE_REASON_EOF: reason = "eof"
        case MPV_END_FILE_REASON_STOP: reason = "stop"
        case MPV_END_FILE_REASON_QUIT: reason = "quit"
        case MPV_END_FILE_REASON_ERROR: reason = "error"
        case MPV_END_FILE_REASON_REDIRECT: reason = "redirect"
        default: reason = "unknown"
        }
        var errorText: String?
        if end.reason == MPV_END_FILE_REASON_ERROR, end.error < 0 {
            errorText = String(cString: mpv_error_string(end.error))
        }
        DispatchQueue.main.async { [weak self] in
            self?.onEndFile?(reason, errorText)
            if let errorText {
                self?.onError?("Playback failed: \(errorText)")
            }
        }
    }

    private func handlePropertyChange(_ event: UnsafeMutablePointer<mpv_event>) {
        guard let property = UnsafePointer<mpv_event_property>(OpaquePointer(event.pointee.data))?.pointee else { return }
        let name = String(cString: property.name)

        switch name {
        case "time-pos":
            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                state.timeSeconds = value
            }
        case "duration":
            if let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee {
                state.durationSeconds = value
            }
        case "pause":
            if let value = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                state.paused = value
            }
        case "paused-for-cache":
            if let value = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                state.buffering = value
            }
        default:
            return
        }

        let snapshot = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(snapshot)
        }
    }

    private func checkError(_ status: CInt, context: String = "") {
        guard status < 0 else { return }
        let text = "mpv API error\(context.isEmpty ? "" : " (\(context))"): \(String(cString: mpv_error_string(status)))"
        print(text)
        Self.log.error("\(text, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.onError?(text)
        }
    }
}
