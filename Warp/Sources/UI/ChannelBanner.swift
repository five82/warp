import SwiftUI

/// The flip banner: channel number and name, what is on, how far through the
/// block we are, what is next, and the picture's badges. Shows on every flip,
/// on Left/Right, and on a captions toggle, then auto-hides. The CC badge is
/// lit in the channel's hue when captions are on and dim when off; it is the
/// only indication of the global switch, so it is always drawn.
///
/// A glass card with the spectrum along its top edge; the number glows in the
/// channel's hue. The blur samples the video underneath, which is the one
/// piece of GPU work the banner adds over mpv - watch `warp.tune` if it ever
/// looks like it costs a frame.
struct ChannelBanner: View {
    let channel: Channel
    let program: Program?
    let next: Program?
    let now: Date
    let captionsEnabled: Bool

    private static let cornerRadius: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(alignment: .center, spacing: 34) {
                number
                details
                Spacer(minLength: 0)
                if let program {
                    artwork(for: program)
                }
            }
            .padding(.horizontal, 38)
            .padding(.vertical, 34)
            .background(.ultraThinMaterial)
            .background(Color.ground.opacity(0.55))
            .overlay(alignment: .top) { Ramp(height: 4) }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).stroke(Color.ink.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
        .padding(.horizontal, TVLayout.sideMargin)
        .padding(.bottom, TVLayout.verticalMargin)
    }

    private var hue: Color { channelHue(channel.key) }

    private var number: some View {
        VStack(spacing: 6) {
            Text(String(channel.number))
                .font(.system(size: 66, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: hue.opacity(0.45), radius: 12)
            RowLabel(text: channel.name, color: hue, font: .labelSmall, tracking: TypeScale.labelSmall * 0.14)
                .lineLimit(1)
        }
        .frame(minWidth: 110)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        TechBadge(text: badge, color: badge == "HDR" || badge == "DV" ? .amber : .chip)
                    }
                    TechBadge(text: "CC", color: captionsEnabled ? hue : .faint)
                }
                BlockProgress(fraction: blockFraction(program, at: now), color: hue)
                    .frame(width: 700)
                    .padding(.top, 6)
                if let next {
                    Text("Next \u{00B7} \(programTitle(next.item))\(nextDetail)")
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
        }
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
        ChannelArtwork(item: program.item, hue: hue)
            .frame(width: 300, height: 169)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Artwork for a program: an episode's still, else the backdrop, else the
/// poster, else the title set in type.
struct ChannelArtwork: View {
    let item: Item
    var hue: Color = .cobalt
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        ZStack {
            Color.surface1
            if let url = artURL {
                CachedImage(url: url, contentMode: .fill)
            } else {
                MissingArt(title: item.title, tint: hue)
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
            Color.ground.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 18) {
                Ramp(height: 4)
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
