import SwiftUI
import UIKit

/// Holds the display awake while a video is running, and lets it sleep once
/// one is paused or finished - the way other video players behave.
///
/// Holds are counted because picking "Up next" builds the following session
/// before the finished one goes away, and the order of the two is SwiftUI's to
/// choose: clearing the flag outright on disappear could undo the hold the new
/// session had just taken, leaving the display asleep mid-episode.
@MainActor
private enum DisplayAwake {
    private static var holds = 0

    static func hold(_ holding: Bool) {
        holds += holding ? 1 : -1
        UIApplication.shared.isIdleTimerDisabled = holds > 0
    }
}

extension View {
    /// Keeps the display awake while `awake` is true. Pass the player's intent
    /// to play rather than whether frames are moving: buffering has to count as
    /// running, because the display sleeps as soon as the hold drops if the
    /// last touch is already older than the auto-lock, so a rebuffer an hour
    /// into a film would blank the screen at once.
    func keepingDisplayAwake(_ awake: Bool) -> some View {
        modifier(KeepDisplayAwake(awake: awake))
    }
}

private struct KeepDisplayAwake: ViewModifier {
    let awake: Bool
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onChange(of: awake, initial: true) { _, awake in hold(awake) }
            .onDisappear { hold(false) }
    }

    private func hold(_ wanted: Bool) {
        guard wanted != holding else { return }
        holding = wanted
        DisplayAwake.hold(wanted)
    }
}
