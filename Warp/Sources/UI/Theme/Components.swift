import SwiftUI

// The shared pieces of the design system Warp actually uses, copied from
// Takeup's Components.swift.

/// The woven brand stripe: ember, teal, amber, violet in fixed proportion.
struct Selvedge: View {
    var height: CGFloat = 4

    private static let pattern: [(Color, CGFloat)] = [
        (.ember, 0.40), (.teal, 0.29), (.amber, 0.20), (.violet, 0.11),
    ]

    var body: some View {
        GeometryReader { proxy in
            let repeatWidth = min(proxy.size.width, 140)
            let tiles = Int((proxy.size.width / repeatWidth).rounded(.up))
            HStack(spacing: 0) {
                ForEach(0..<max(tiles, 1), id: \.self) { _ in
                    ForEach(0..<Self.pattern.count, id: \.self) { index in
                        Self.pattern[index].0
                            .frame(width: repeatWidth * Self.pattern[index].1)
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2))
    }
}

/// Progress drawn as a thread being woven: a thin line in the given color
/// brightening toward its end, on a faint unwoven track.
struct ThreadProgress: View {
    var fraction: Double
    var color: Color
    var tipColor: Color?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color.opacity(0.18))
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [color, tipColor ?? color.opacity(0.65)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Artwork fallback: the title set in the display voice over a Surface1 field,
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

/// Outlined uppercase tech badge: 4K, HDR, HEVC.
struct TechBadge: View {
    var text: String
    var color: Color = .muted

    var body: some View {
        Text(text.uppercased())
            .font(.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.55), lineWidth: 1))
    }
}

/// "The loom is dark" - errors carry the brand voice, over a short selvedge.
struct ErrorState: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Selvedge(height: 4)
                .frame(width: 110)
            Text("The loom is dark")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.bodyMedium)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(TVPillButtonStyle(fill: .ember, onFill: Color(hexValue: 0x33060A)))
                    .padding(.top, 10)
            }
        }
        .padding(40)
        .frame(maxWidth: 900)
    }
}
