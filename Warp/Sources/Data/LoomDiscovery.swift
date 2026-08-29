import Foundation
import Network
import Observation

/// Browses Bonjour for Loom's `_loom._tcp` service and resolves each hit to
/// an http URL. Resolution goes through a throwaway TCP connection because
/// NWBrowser only hands back service endpoints, not host/port pairs.
@Observable
@MainActor
final class LoomDiscovery {
    struct Server: Identifiable, Hashable {
        let name: String
        let urlString: String

        var id: String { name + urlString }
    }

    private(set) var servers: [Server] = []
    private var browser: NWBrowser?
    private var resolvers: [NWConnection] = []

    func start() {
        stop()
        servers = []
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_loom._tcp", domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.resolve(results)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.forEach { $0.cancel() }
        resolvers = []
    }

    private func resolve(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            // Prefer IPv4: v6 SLAAC addresses rotate, making saved URLs stale.
            let parameters = NWParameters.tcp
            if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: result.endpoint, using: parameters)
            resolvers.append(connection)
            connection.stateUpdateHandler = { [weak self] state in
                guard case .ready = state else { return }
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = endpoint {
                    // Addresses off a connection path carry an interface
                    // scope suffix (10.0.0.5%en0) that URLs reject; strip it.
                    func bare(_ description: String) -> String {
                        description.components(separatedBy: "%").first ?? description
                    }
                    let hostText: String
                    switch host {
                    case .ipv4(let address):
                        hostText = bare("\(address)")
                    case .ipv6(let address):
                        hostText = "[\(bare("\(address)"))]"
                    case .name(let hostname, _):
                        hostText = hostname
                    @unknown default:
                        hostText = "\(host)"
                    }
                    Task { @MainActor in
                        self?.add(Server(name: name, urlString: "http://\(hostText):\(port)"))
                    }
                }
                connection.cancel()
            }
            connection.start(queue: .main)
        }
    }

    private func add(_ server: Server) {
        if !servers.contains(server) {
            servers.append(server)
        }
    }
}
