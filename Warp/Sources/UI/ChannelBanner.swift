import SwiftUI

/// The flip banner: channel number and name, what is on, how far through the
/// block we are, what is next, and the picture's badges. Shows on every flip
/// and on Left/Right, then auto-hides.
///
/// Play/Pause opens the same banner as the player panel: `captions` is set,
/// a CC pill takes focus, and it stays until Menu or Play/Pause closes it. A
/// channel has no transport, so this is the whole of the player controls.
struct ChannelBanner: View {
    let channel: Channel
    let program: Program?
    let next: Program?
    let now: Date
    var captions: CaptionsControl?

    @FocusState private var captionsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(alignment: .top, spacing: 30) {
                number
                details
                Spacer(minLength: 0)
                if let program {
                    artwork(for: program)
                }
            }
            .padding(34)
            .background(Color(hexValue: 0x0A0E17).opacity(0.78), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.ink.opacity(0.14), lineWidth: 1))
        }
        .padding(.horizontal, TVLayout.sideMargin)
        .padding(.bottom, TVLayout.verticalMargin)
    }

    private var thread: Color { channelThread(channel.kind) }

    private var number: some View {
        VStack(spacing: 6) {
            Text(String(channel.number))
                .font(.displayMedium.monospacedDigit())
                .foregroundStyle(thread)
            Selvedge(height: 4)
                .frame(width: 60)
        }
        .frame(minWidth: 96)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            RowLabel(text: channel.name, color: .muted)
            if let program {
                Text(programTitle(program.item))
                    .font(.titleLarge)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                if let subtitle = programSubtitle(program.item) {
                    Text(subtitle)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
                HStack(spacing: 16) {
                    Text(programTimeRange(program))
                        .font(.labelMedium.monospacedDigit())
                        .foregroundStyle(Color.muted)
                    ForEach(videoBadges(program.video), id: \.self) { badge in
                        TechBadge(text: badge, color: badge == "HDR" || badge == "DV" ? .amber : .muted)
                    }
                }
                ThreadProgress(fraction: blockFraction(program, at: now), color: thread)
                    .frame(width: 700)
                    .padding(.top, 4)
                if let next {
                    Text("Next: \(programTitle(next.item))\(nextDetail)")
                        .font(.bodySmall)
                        .foregroundStyle(Color.faint)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
            } else {
                Text("Nothing scheduled")
                    .font(.titleLarge)
                    .foregroundStyle(Color.ink)
            }
            if let captions {
                controls(captions)
            }
        }
    }

    private func controls(_ captions: CaptionsControl) -> some View {
        HStack(spacing: 16) {
            Button(action: captions.toggle) {
                HStack(spacing: 10) {
                    TechBadge(text: "CC", color: captions.enabled ? thread : .muted)
                    Text(captions.enabled ? "Captions on" : "Captions off")
                }
            }
            .buttonStyle(TVPillButtonStyle())
            .focused($captionsFocused)
            // The pill is the only focusable thing on screen while the panel
            // is up; Up/Down keep flipping channels from it.
            .onMoveCommand { direction in
                switch direction {
                case .up: captions.channelUp()
                case .down: captions.channelDown()
                default: break
                }
            }
        }
        .padding(.top, 14)
        .onAppear { captionsFocused = true }
    }

    private var nextDetail: String {
        guard let next else { return "" }
        let bits = [programSubtitle(next.item), formatTimeOfDay(next.startsAt)].compactMap { $0 }
        return bits.isEmpty ? "" : " \u{00B7} " + bits.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private func artwork(for program: Program) -> some View {
        // The banner is the only place Warp shows artwork, so it takes the
        // 16:9 still an episode wears and the poster otherwise.
        ChannelArtwork(item: program.item, thread: thread)
            .frame(width: 300, height: 169)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// What the panel needs from the tuner: the CC state and the three presses it
/// handles itself.
struct CaptionsControl {
    var enabled: Bool
    var toggle: () -> Void
    var channelUp: () -> Void
    var channelDown: () -> Void
}

/// Artwork for a program: an episode's still, else the backdrop, else the
/// poster, else the title set in type.
struct ChannelArtwork: View {
    let item: Item
    var thread: Color = .ember
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        ZStack {
            Color.surface1
            if let url = artURL {
                CachedImage(url: url, contentMode: .fill)
            } else {
                MissingArt(title: item.title, tint: thread)
            }
        }
    }

    private var artURL: URL? {
        guard let client = appEnvironment.client else { return nil }
        if item.kind == "episode",
           let url = client.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: 480) {
            return url
        }
        return client.imageURL(id: item.backdropImageId, tag: item.backdropImageTag, width: 480)
            ?? client.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: 480)
            ?? client.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 480)
    }
}

/// Section 2.4: the program is scheduled but this box can not decode it. Stay
/// tuned; the next block takes over on its own.
struct UnplayableCard: View {
    let channel: Channel
    let program: Program?
    let next: Program?
    let reason: String

    var body: some View {
        ZStack {
            Color.stage.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Selvedge(height: 4)
                    .frame(width: 110)
                Text("This Apple TV can't play this program")
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
                if let program {
                    Text([programTitle(program.item), programSubtitle(program.item)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                        .font(.titleSmall)
                        .foregroundStyle(Color.muted)
                }
                Text(reason)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.faint)
                if let next {
                    Text("Next on \(channel.number) \(channel.name): \(programTitle(next.item)) at \(formatTimeOfDay(next.startsAt))")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 10)
                }
            }
            .multilineTextAlignment(.center)
            .padding(50)
        }
    }
}
