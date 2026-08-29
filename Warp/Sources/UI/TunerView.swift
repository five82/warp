import SwiftUI

/// The app's home: full-screen video with the channel banner and the guide as
/// overlays. It launches straight into the last channel; there are no
/// transport controls, because a channel has no transport.
///
/// Remote grammar (docs/proposal.md 4.3):
///   Up/Down      channel +/-, wrapping
///   Select       toggle the guide
///   Left/Right   show the banner
///   Menu         close the guide, else leave the app
///   Play/Pause   show the banner
struct TunerView: View {
    let client: LoomClient
    let options: LaunchOptions
    let openSettings: () -> Void

    @State private var host = PlayerHost()
    @State private var tuner: Tuner
    @State private var guideVisible: Bool
    @State private var bannerVisible = true
    /// Any interaction bumps this; the banner's auto-hide countdown restarts.
    @State private var bannerTick = 0
    /// Redraws the banner's progress bar and the guide's clock once a second.
    @State private var clockTick = Date()

    init(client: LoomClient, options: LaunchOptions, openSettings: @escaping () -> Void) {
        self.client = client
        self.options = options
        self.openSettings = openSettings
        _tuner = State(initialValue: Tuner(
            client: client,
            frozen: options.frozenClock,
            startChannel: options.channel
        ))
        _guideVisible = State(initialValue: options.guideOpen)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MPVPlayerView(controller: host.controller)
                .ignoresSafeArea()

            if let reason = tuner.blockedReason, let channel = tuner.channel {
                UnplayableCard(
                    channel: channel,
                    program: tuner.current,
                    next: tuner.next,
                    reason: reason
                )
            }

            if tuner.offAir, tuner.blockedReason == nil {
                offAirCard
            }

            if let error = tuner.loadError, tuner.lineup == nil {
                ZStack {
                    ThreeThreads(colors: [RGB(hexValue: 0xFF4D55), RGB(hexValue: 0x3FD1C4), RGB(hexValue: 0xA78BFA)])
                    ErrorState(message: error) {
                        Task { await tuner.refresh() }
                    }
                }
            }

            if !guideVisible {
                remoteCatcher
            }

            if bannerVisible, !guideVisible, let channel = tuner.channel {
                ChannelBanner(
                    channel: channel,
                    program: tuner.current,
                    next: tuner.next,
                    now: tuner.serverNow
                )
                .transition(.opacity)
            }

            if guideVisible, let lineup = tuner.lineup {
                GuideView(
                    lineup: lineup,
                    currentNumber: tuner.channelNumber,
                    now: tuner.serverNow,
                    onSelect: { number in
                        tuner.tune(to: number)
                        closeGuide()
                    },
                    onSettings: openSettings
                )
                .transition(.opacity)
            }
        }
        // Menu closes the guide when it is open; with no handler installed the
        // system default (leave the app) runs, which is what tvOS expects.
        .onExitCommand(perform: guideVisible ? { closeGuide() } : nil)
        .onPlayPauseCommand { showBanner() }
        .task {
            tuner.attach(host.controller)
            await tuner.run()
        }
        .task {
            guard let count = options.surf else { return }
            // Give the first tune time to land before the run starts.
            try? await Task.sleep(for: .seconds(6))
            await tuner.surf(count)
        }
        // Every tune (a flip or a block boundary) shows the banner.
        .onChange(of: tuner.tuneTick) { _, _ in showBanner() }
        .task(id: bannerTick) {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { bannerVisible = false }
        }
        // The banner's progress bar and the guide's clock tick once a second.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                clockTick = Date()
            }
        }
        // A channel is always playing, so the display never sleeps while Warp
        // is open.
        .keepingDisplayAwake(true)
    }

    /// The only focusable thing on screen while the guide is closed: it turns
    /// remote presses into channel changes. The mpv view is not focusable and
    /// the focus engine needs somewhere to stand.
    private var remoteCatcher: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { guideVisible = true }
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        // Not .plain: the system styles paint their white focus/press
        // highlight over the label, and this label is the whole screen - the
        // video visibly washes out under it.
        .buttonStyle(TVInvisibleButtonStyle())
        .onMoveCommand { direction in
            switch direction {
            case .up:
                tuner.channelUp()
                showBanner()
            case .down:
                tuner.channelDown()
                showBanner()
            default:
                showBanner()
            }
        }
        .ignoresSafeArea()
    }

    private var offAirCard: some View {
        ZStack {
            Color.stage.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                Selvedge(height: 4).frame(width: 110)
                Text("Off air")
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
                Text("Nothing is scheduled on this channel right now.")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private func showBanner() {
        withAnimation(.easeInOut(duration: 0.2)) { bannerVisible = true }
        bannerTick += 1
    }

    private func closeGuide() {
        withAnimation(.easeInOut(duration: 0.2)) { guideVisible = false }
        showBanner()
    }
}
