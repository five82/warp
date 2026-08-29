import Foundation
import Observation

/// App-wide state: the configured Loom server and the API client built from it.
/// The Apple TV always lives on the Loom LAN, so there is no offline story here
/// and failures surface as plain errors.
@Observable
@MainActor
final class AppEnvironment {
    private static let serverKey = "loom.server.url"

    var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverKey)
        }
    }

    init() {
        // No default: the server address lives in Settings, never in the repo.
        serverURLString = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
    }

    var serverURL: URL? {
        Self.normalize(serverURLString)
    }

    // Pure, and used from tests off the main actor.
    nonisolated static func normalize(_ address: String) -> URL? {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        guard var components = URLComponents(string: raw) else { return nil }
        // Only cleartext LAN addresses get Loom's default port. An https name
        // is already whole, and :8097 would break it.
        if components.scheme == "http", components.port == nil { components.port = 8097 }
        return components.url
    }

    var client: LoomClient? {
        serverURL.map { LoomClient(baseURL: $0) }
    }
}
