import SwiftUI

/// One soft glow low on an otherwise empty ground: the onboarding and error
/// backgrounds. Still, so it costs nothing while the tuner is idle behind it.
struct Glow: View {
    var color: Color = .cobalt

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                Color.ground
                RadialGradient(
                    colors: [color.opacity(0.22), .clear],
                    center: .center, startRadius: 0, endRadius: 0.6 * w
                )
                .frame(width: 1.2 * w, height: 1.2 * w)
                .position(x: 0.5 * w, y: 0.8 * proxy.size.height)
            }
        }
        .ignoresSafeArea()
    }
}
