import SwiftUI

/// First run and the settings screen in one: Bonjour-discovered servers lead,
/// typing an address with a remote is the fallback, and the address commits
/// only after a successful health check. Straight from Takeup.
struct OnboardingView: View {
    var title: String = "Warp"
    var onDone: (() -> Void)?

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var discovery = LoomDiscovery()
    @State private var draft = ""
    @State private var connecting = false
    @State private var connectError: String?

    var body: some View {
        ZStack {
            Glow()
            VStack(spacing: 0) {
                Spacer()

                Ramp()
                    .frame(width: 140)
                Text(title)
                    .font(.displayLarge)
                    .foregroundStyle(Color.ink)
                    .padding(.top, 26)
                Text("linear TV for Loom")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 6)

                VStack(spacing: 18) {
                    if !discovery.servers.isEmpty {
                        ForEach(discovery.servers) { server in
                            Button {
                                Task { await connect(to: server.urlString) }
                            } label: {
                                HStack(spacing: 20) {
                                    Image(systemName: "server.rack")
                                        .foregroundStyle(Color.cobalt)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.titleSmall)
                                            .foregroundStyle(Color.ink)
                                        Text(server.urlString)
                                            .font(.labelSmall)
                                            .foregroundStyle(Color.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(Color.muted)
                                }
                            }
                            .buttonStyle(TVRowButtonStyle())
                        }
                    } else {
                        HStack(spacing: 14) {
                            ProgressView()
                                .tint(.cobalt)
                            Text("Looking for Loom on your network\u{2026}")
                                .font(.bodyMedium)
                                .foregroundStyle(Color.muted)
                        }
                        .padding(.vertical, 6)
                    }

                    TextField(
                        "Server address",
                        text: $draft,
                        prompt: Text(verbatim: "192.168.1.20:8097").foregroundStyle(Color.faint)
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await connect(to: draft) } }

                    HStack(spacing: 20) {
                        Button(connecting ? "Connecting\u{2026}" : "Connect") {
                            Task { await connect(to: draft) }
                        }
                        .buttonStyle(TVPillButtonStyle(fill: .cobalt, onFill: Color(hexValue: 0x08182F)))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                        .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty || connecting ? 0.5 : 1)

                        if let onDone {
                            Button("Back", action: onDone)
                                .buttonStyle(TVPillButtonStyle())
                        }
                    }

                    if let connectError {
                        Text(connectError)
                            .font(.bodyMedium)
                            .foregroundStyle(Color.ember)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 760)
                .padding(.top, 50)

                Spacer()
                Spacer()
            }
            .padding(TVLayout.sideMargin)
        }
        .background(Color.ground)
        .onAppear {
            discovery.start()
            draft = appEnvironment.serverURLString
        }
        .onDisappear { discovery.stop() }
        .onExitCommand(perform: onDone)
    }

    private func connect(to address: String) async {
        guard let url = AppEnvironment.normalize(address) else {
            connectError = "That doesn't look like a server address."
            return
        }
        connecting = true
        connectError = nil
        do {
            try await LoomClient(baseURL: url).health()
            // Committing the address flips RootView over to the tuner.
            appEnvironment.serverURLString = address
            onDone?()
        } catch {
            connectError = "Couldn't reach Loom there: \(error.localizedDescription)"
        }
        connecting = false
    }
}
