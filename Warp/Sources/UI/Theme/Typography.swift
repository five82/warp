import SwiftUI

// SF Pro with the Takeup scale and the uppercase tracked label voice. tvOS
// only: the sizes are anchored to tvOS's system text styles (body 29, title
// 57/76) so the app reads correctly at ten feet.

enum TypeScale {
    static let displayLarge: CGFloat = 76
    static let displayMedium: CGFloat = 57
    static let displaySmall: CGFloat = 46
    static let headlineMedium: CGFloat = 38
    static let titleLarge: CGFloat = 36
    static let titleMedium: CGFloat = 31
    static let titleSmall: CGFloat = 27
    static let bodyLarge: CGFloat = 29
    static let bodyMedium: CGFloat = 26
    static let bodySmall: CGFloat = 23
    static let labelLarge: CGFloat = 26
    static let labelMedium: CGFloat = 23
    static let labelSmall: CGFloat = 21
}

extension Font {
    static let displayLarge = Font.system(size: TypeScale.displayLarge, weight: .semibold)
    static let displayMedium = Font.system(size: TypeScale.displayMedium, weight: .semibold)
    static let displaySmall = Font.system(size: TypeScale.displaySmall, weight: .semibold)
    static let headlineMedium = Font.system(size: TypeScale.headlineMedium, weight: .semibold)
    static let titleLarge = Font.system(size: TypeScale.titleLarge, weight: .semibold)
    static let titleMedium = Font.system(size: TypeScale.titleMedium, weight: .semibold)
    static let titleSmall = Font.system(size: TypeScale.titleSmall, weight: .medium)
    static let bodyLarge = Font.system(size: TypeScale.bodyLarge)
    static let bodyMedium = Font.system(size: TypeScale.bodyMedium)
    static let bodySmall = Font.system(size: TypeScale.bodySmall)
    static let labelLarge = Font.system(size: TypeScale.labelLarge, weight: .semibold)
    static let labelMedium = Font.system(size: TypeScale.labelMedium, weight: .semibold)
    static let labelSmall = Font.system(size: TypeScale.labelSmall, weight: .medium)
}

/// The signature row-label voice: uppercase, semibold, +0.14em tracking.
struct RowLabel: View {
    let text: String
    var color: Color = .muted
    var font: Font = .labelMedium
    var tracking: CGFloat = TypeScale.labelMedium * 0.14

    var body: some View {
        Text(text.uppercased())
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
    }
}
