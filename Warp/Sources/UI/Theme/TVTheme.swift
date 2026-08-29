import SwiftUI

/// TV layout constants and focus treatments, copied from Takeup's TVTheme.
enum TVLayout {
    /// The overscan-safe margins, per the tvOS layout guidance.
    static let sideMargin: CGFloat = 80
    static let verticalMargin: CGFloat = 60
}

/// Focus-aware capsule for pills and chips: the fill brightens under focus and
/// the text flips to its on-color, so the focused control is unmistakable from
/// the couch.
struct TVPillButtonStyle: ButtonStyle {
    var fill: Color = .ink
    var onFill: Color = Color(hexValue: 0x171B26)
    var idleFill: Color?
    var idleText: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(
            configuration: configuration,
            fill: fill, onFill: onFill,
            idleFill: idleFill ?? fill.opacity(0.10), idleText: idleText
        )
    }

    private struct PillLabel: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration
        let fill: Color
        let onFill: Color
        let idleFill: Color
        let idleText: Color

        var body: some View {
            configuration.label
                .font(.labelLarge)
                .lineLimit(1)
                .foregroundStyle(focused ? onFill : idleText)
                .padding(.horizontal, 32)
                .frame(minHeight: 64)
                .background(focused ? fill : idleFill, in: Capsule())
                .scaleEffect(focused ? 1.05 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Focus-aware full-width row: the frosted ink card used by the server list.
struct TVRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowLabelView(configuration: configuration)
    }

    private struct RowLabelView: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    focused ? Color.ink.opacity(0.18) : Color.ink.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? Color.ink.opacity(0.6) : Color.ink.opacity(0.10), lineWidth: focused ? 2 : 1)
                )
                .scaleEffect(focused ? 1.02 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// A button that stays focusable but draws no focus or press treatment at all.
///
/// Critical for the tuner's remote catcher: the system styles (`.plain`
/// included) paint their white focus/press highlight over the button's label,
/// and that label is the whole screen - the video visibly washes out to
/// near-white under it, on the simulator constantly and on the hardware
/// whenever the highlight engages. A custom style that returns the bare label
/// draws nothing and stays focusable.
struct TVInvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Focus-aware guide cell: a program block in the grid.
struct TVGuideCellStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        CellLabel(configuration: configuration, accent: accent)
    }

    private struct CellLabel: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration
        let accent: Color

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    focused ? accent.opacity(0.32) : Color.surface1.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(focused ? accent : Color.line, lineWidth: focused ? 3 : 1)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}
