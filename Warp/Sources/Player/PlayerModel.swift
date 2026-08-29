import SwiftUI

/// The SwiftUI bridge to the one long-lived MPVPlayerController. The
/// controller is created and owned outside the representable so a SwiftUI
/// rebuild can never tear mpv down mid-surf.
struct MPVPlayerView: UIViewControllerRepresentable {
    let controller: MPVPlayerController

    func makeUIViewController(context: Context) -> MPVPlayerController { controller }

    func updateUIViewController(_ uiViewController: MPVPlayerController, context: Context) {}
}

/// Owns the controller for the life of the tuner screen.
@MainActor
final class PlayerHost {
    let controller = MPVPlayerController()

    deinit {
        // MPVPlayerController's own deinit shuts mpv down; this is only here
        // so the intent is obvious at the ownership site.
    }
}
