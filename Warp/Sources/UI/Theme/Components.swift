import SwiftUI

// The shared pieces of Warp's design system.

/// The mark: the spectrum as a thin rounded bar, teal to amber.
struct Ramp: View {
    var height: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(LinearGradient.spectrum)
            .frame(height: height)
    }
}

/// How far through the block we are: a solid bar in the channel's hue on a
/// faint neutral track. The banner's crown already carries the spectrum.
struct BlockProgress: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.ink.opacity(0.10))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Artwork fallback: the title set in the label voice over a Surface1 field,
/// under a short tinted rule.
struct MissingArt: View {
    var title: String
    var tint: Color

    var body: some View {
        ZStack {
            Color.surface1
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint.opacity(0.85))
                    .frame(width: 34, height: 4)
                Text(title.uppercased())
                    .font(.labelSmall)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .padding(14)
        }
    }
}

/// Filled uppercase tech chip: 4K, HDR, HEVC, CC. Tinted with its colour at
/// low alpha rather than outlined.
struct TechBadge: View {
    var text: String
    var color: Color = .chip

    var body: some View {
        Text(text.uppercased())
            .font(.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// "No signal" - the app can not reach Loom at all.
struct ErrorState: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Ramp(height: 4)
                .frame(width: 110)
            Text("No signal")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.bodyMedium)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(TVPillButtonStyle(fill: .cobalt, onFill: Color(hexValue: 0x08182F)))
                    .padding(.top, 10)
            }
        }
        .padding(40)
        .frame(maxWidth: 900)
    }
}
