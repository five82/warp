import SwiftUI

/// Launch arguments for CLI-driven checks (see AGENTS.md).
struct LaunchOptions {
    var server: String?
    var channel: Int?
    var guideOpen = false
    var frozenClock = false
    /// `-surf <n>`: auto-flip channels n times, 8 seconds apart, logging each.
    var surf: Int?

    static func parse(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchOptions {
        var options = LaunchOptions()
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        options.server = value(after: "-server")
        options.channel = value(after: "-channel").flatMap(Int.init)
        options.guideOpen = arguments.contains("-guide")
        options.frozenClock = arguments.contains("-freeze")
        options.surf = value(after: "-surf").flatMap(Int.init)
        return options
    }
}

/// Onboarding until a server is configured, then the tuner. There is nothing
/// else: Warp is one screen with overlays.
struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var options = LaunchOptions.parse()
    @State private var showSettings = false

    var body: some View {
        Group {
            if appEnvironment.client == nil {
                OnboardingView()
            } else if showSettings {
                OnboardingView(title: "Loom", onDone: { showSettings = false })
            } else if let client = appEnvironment.client {
                TunerView(client: client, options: options, openSettings: { showSettings = true })
                    // A new server address means a new lineup and a new player.
                    .id(appEnvironment.serverURLString)
            }
        }
        .background(Color.ground)
        .onAppear {
            if let server = options.server, !server.isEmpty {
                appEnvironment.serverURLString = server
            }
        }
    }
}
