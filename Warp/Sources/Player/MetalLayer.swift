import UIKit

/// CAMetalLayer with the MoltenVK workaround from the MPVKit demo: MoltenVK
/// forces drawableSize to 1x1 to complete presentation, which flickers and can
/// stick (mpv-player/mpv#13651).
///
/// tvOS has no wantsExtendedDynamicRangeContent: the Apple TV negotiates HDR
/// output at the system level, and Warp pins that mode once at launch (see
/// DisplayModePinner). The layer's `colorspace`, which mpv sets from
/// target-colorspace-hint, is what tells CoreAnimation how to read our pixels.
final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
