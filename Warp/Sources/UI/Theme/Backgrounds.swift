import SwiftUI

/// Three soft color fields drifting behind an otherwise empty screen: the
/// onboarding and error grounds. Copied from Takeup's Backgrounds.swift.
struct ThreeThreads: View {
    var colors: [RGB]
    var drifting = false

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var t1 = 0.5
    @State private var t2 = 0.5

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let tones = colors.map { $0.fieldTone().color }
            let sway1 = (t1 - 0.5) * 0.12 * w
            let sway2 = (t2 - 0.5) * 0.12 * w
            ZStack {
                Color.stage
                if tones.count > 0 {
                    blob(tones[0], alpha: 0.30, radius: 0.70 * w,
                         x: 0.12 * w + sway1, y: 0.18 * h + sway2 * 0.5)
                }
                if tones.count > 1 {
                    blob(tones[1], alpha: 0.24, radius: 0.80 * w,
                         x: 0.92 * w - sway1, y: 0.42 * h - sway2 * 0.5)
                }
                if tones.count > 2 {
                    blob(tones[2], alpha: 0.26, radius: 0.85 * w,
                         x: 0.35 * w + sway2, y: 0.98 * h + sway1 * 0.5)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard drifting, !reducedMotion else { return }
            withAnimation(.linear(duration: 21).repeatForever(autoreverses: true)) { t1 = 1 }
            withAnimation(.linear(duration: 27).repeatForever(autoreverses: true)) { t2 = 1 }
        }
    }

    private func blob(_ color: Color, alpha: Double, radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(alpha), .clear], center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: x, y: y)
    }
}
