import SwiftUI

// The Takeup palette, copied verbatim. The system is a loom metaphor: Stage is
// the unlit loom - deep indigo, never pure black - and the threads color the
// app's worlds. Warp uses a small slice of it.

extension Color {
    // Neutrals.
    static let stage = Color(hexValue: 0x0B0E14)
    static let surface1 = Color(hexValue: 0x131826)
    static let surface2 = Color(hexValue: 0x1A2032)
    static let line = Color(hexValue: 0x232B3F)
    static let ink = Color(hexValue: 0xE9EDF6)
    static let muted = Color(hexValue: 0x8C96AB)
    static let faint = Color(hexValue: 0x5C667C)

    // Brand threads.
    static let ember = Color(hexValue: 0xFF4D55)
    static let teal = Color(hexValue: 0x3FD1C4)
    static let amber = Color(hexValue: 0xFFB84D)
    static let violet = Color(hexValue: 0xA78BFA)
    static let cobalt = Color(hexValue: 0x5FA0FF)

    init(hexValue: UInt32) {
        self.init(
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255
        )
    }
}

/// The thread a channel wears, chosen by its key so a channel keeps its color
/// across launches and across lineup edits around it. The lineup is hand-built
/// on the server with no kind field, so there is nothing more meaningful to
/// color by.
func channelThread(_ key: String) -> Color {
    let threads: [Color] = [.teal, .cobalt, .amber, .ember]
    // FNV-1a, so the choice does not depend on Swift's per-process hash seed.
    var hash: UInt32 = 2_166_136_261
    for byte in key.utf8 {
        hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return threads[Int(hash % UInt32(threads.count))]
}

/// A color as plain RGB in [0, 1], for the HSV math the background treatments
/// need. SwiftUI's Color hides its components.
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hexValue: UInt32) {
        r = Double((hexValue >> 16) & 0xFF) / 255
        g = Double((hexValue >> 8) & 0xFF) / 255
        b = Double(hexValue & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    var hsv: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    static func fromHSV(h: Double, s: Double, v: Double) -> RGB {
        let c = v * s
        let hPrime = (h.truncatingRemainder(dividingBy: 360) / 60)
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) = switch Int(hPrime) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        let m = v - c
        return RGB(r: r1 + m, g: g1 + m, b: b1 + m)
    }

    /// The tone every background treatment paints with: hue untouched,
    /// saturation floored at 0.30, value clamped to [0.48, 0.62].
    func fieldTone() -> RGB {
        let (h, s, v) = hsv
        return RGB.fromHSV(h: h, s: max(s, 0.30), v: min(max(v, 0.48), 0.62))
    }

    /// Per-channel lightening toward white - the bright tip of a progress
    /// thread.
    func lightened(_ fraction: Double) -> RGB {
        RGB(r: r + (1 - r) * fraction, g: g + (1 - g) * fraction, b: b + (1 - b) * fraction)
    }
}
