import SwiftUI

// Warp's palette. The ground is a true near-black so hue reads pure against
// it; the five hues are the stops of the spectrum ramp, the app's mark, and a
// channel takes its colour from one of them.

extension Color {
    // Neutrals.
    static let ground = Color(hexValue: 0x08090C)
    static let surface1 = Color(hexValue: 0x111318)
    static let surface2 = Color(hexValue: 0x181B22)
    static let line = Color(hexValue: 0x22262F)
    static let ink = Color(hexValue: 0xE9EDF6)
    static let chip = Color(hexValue: 0xC9CFDB)
    static let muted = Color(hexValue: 0x8C96AB)
    static let faint = Color(hexValue: 0x5C667C)

    // The spectrum, in ramp order.
    static let teal = Color(hexValue: 0x3FD1C4)
    static let cobalt = Color(hexValue: 0x5FA0FF)
    static let violet = Color(hexValue: 0xA78BFA)
    static let ember = Color(hexValue: 0xFF4D55)
    static let amber = Color(hexValue: 0xFFB84D)

    /// The ramp's stops, teal to amber.
    static let spectrum: [Color] = [.teal, .cobalt, .violet, .ember, .amber]

    init(hexValue: UInt32) {
        self.init(
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255
        )
    }
}

/// The spectrum as a gradient, left to right.
extension LinearGradient {
    static let spectrum = LinearGradient(colors: Color.spectrum, startPoint: .leading, endPoint: .trailing)
}

/// Which stop of the ramp a channel wears, chosen by its key so a channel
/// keeps its colour across launches and across lineup edits around it. The
/// lineup is hand-built on the server with no kind field, so there is nothing
/// more meaningful to colour by.
private func spectrumIndex(_ key: String) -> Int {
    // FNV-1a, so the choice does not depend on Swift's per-process hash seed.
    var hash: UInt32 = 2_166_136_261
    for byte in key.utf8 {
        hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return Int(hash % UInt32(Color.spectrum.count))
}

/// The channel's hue.
func channelHue(_ key: String) -> Color {
    Color.spectrum[spectrumIndex(key)]
}
