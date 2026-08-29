import SwiftUI
import AVFAudio

@main
struct WarpApp: App {
    @State private var environment = AppEnvironment()
    @State private var pinner = DisplayModePinner()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Dark-only: a television lives in a dim room, and the video
                // is the screen.
                .preferredColorScheme(.dark)
                .tint(.ember)
                .environment(environment)
                .onAppear {
                    // The window exists by the time the root view appears.
                    pinner.pin()
                }
                .onChange(of: scenePhase) { _, phase in
                    // Whether the box drops the criteria on background or
                    // screensaver is undocumented, so re-apply on foreground.
                    if phase == .active { pinner.pin() }
                }
        }
    }
}
