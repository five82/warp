import AVFoundation
import AVKit
import CoreMedia
import Foundation
import UIKit
import os

/// Pins the Apple TV's display mode to HDR10 (BT.2020 / PQ) 4K at 60 Hz, once
/// at launch and again on foreground, and never touches it after that
/// (docs/proposal.md 2.2).
///
/// The point is the HDMI resync. With Match Content on, the box renegotiates
/// the link on every HDR<->SDR boundary - 1-8 seconds of black, worse through
/// an AVR - which would fire on almost every channel flip. Pinning the mode
/// means the box switches once when Warp opens and once when it exits, and
/// mpv's pinned PQ output (see MPVPlayerController) fills that container for
/// SDR and HDR sources alike.
///
/// `preferredDisplayCriteria` is only honored when the user's Match Content
/// setting allows it; `isDisplayCriteriaMatchingEnabled` says whether it does,
/// and is logged at launch so a "nothing happened" report can be explained.
@MainActor
final class DisplayModePinner {
    private static let log = Logger(subsystem: "xyz.five82.warp", category: "display")

    private var observing = false
    private var loggedMatchingState = false

    /// HDR10 HEVC 4K: the format description is how AVDisplayCriteria expresses
    /// "HDR10", since it has no dynamic-range parameter of its own.
    private static func hdr10FormatDescription() -> CMVideoFormatDescription? {
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
            kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
            kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
        ]
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_HEVC,
            width: 3840,
            height: 2160,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )
        guard status == noErr else {
            log.error("warp.display format description failed: \(status)")
            return nil
        }
        return description
    }

    /// Apply the pin. Safe to call repeatedly; the box ignores a criteria it is
    /// already showing.
    func pin() {
        guard let window = Self.keyWindow() else {
            log("warp.display no window yet; pin deferred")
            return
        }
        // The category lives in AVKit, which the linker only loads if something
        // references it; touching the class guarantees that (project.yml also
        // links the framework explicitly). The tvOS simulator's UIKit still
        // does not implement the category - reading the property there raises
        // "unrecognized selector" and takes the app down - and there is no
        // display to pin in the simulator anyway, so skip it and carry on.
        _ = AVDisplayManager.self
        guard window.responds(to: Selector(("avDisplayManager"))) else {
            log("warp.display avDisplayManager unavailable (simulator); no pin")
            return
        }
        let manager = window.avDisplayManager
        if !loggedMatchingState {
            loggedMatchingState = true
            log("warp.display isDisplayCriteriaMatchingEnabled=\(manager.isDisplayCriteriaMatchingEnabled)")
        }
        startObserving()
        guard manager.isDisplayCriteriaMatchingEnabled else {
            // Matching off: the criteria is ignored and the box stays in
            // whatever Format the user set. Warp's PQ output still looks right
            // there as long as that format is HDR.
            log("warp.display criteria matching disabled; leaving the display mode alone")
            return
        }
        guard let formatDescription = Self.hdr10FormatDescription() else { return }
        // 60 Hz, deliberately: the UI wants it, the library mixes every frame
        // rate there is, and a rate switch is an HDMI resync just like a range
        // switch. 24p content takes 3:2 pulldown, as it does in Takeup today.
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: 60, formatDescription: formatDescription)
        log("warp.display pinned HDR10 3840x2160 @60Hz")
    }

    /// Mode-switch notifications, logged with timestamps: the evidence that no
    /// resync happens while surfing channels.
    private func startObserving() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSNotification.Name("AVDisplayManagerModeSwitchStartNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.log("warp.display modeSwitchStart")
        }
        center.addObserver(
            forName: NSNotification.Name("AVDisplayManagerModeSwitchEndNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.log("warp.display modeSwitchEnd")
        }
        center.addObserver(
            forName: NSNotification.Name("AVDisplayManagerModeSwitchSettingsChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.log("warp.display modeSwitchSettingsChanged")
        }
    }

    // Called from notification closures delivered on the main queue, which
    // Swift's isolation checker can not see; nothing here touches instance
    // state, so it is plain nonisolated.
    private nonisolated func log(_ message: String) {
        let line = "\(Self.stamp()) \(message)"
        Self.log.info("\(line, privacy: .public)")
        print(line)
    }

    private nonisolated static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    /// tvOS gives an app one window; find it through the active scene rather
    /// than threading a UIViewControllerRepresentable through the view tree.
    private static func keyWindow() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) { return key }
            if let first = windowScene.windows.first { return first }
        }
        return nil
    }
}
