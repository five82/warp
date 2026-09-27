import Network
import Testing
@testable import Warp

@MainActor
@Suite struct LoomDiscoveryTests {
    @Test func resolvedIPv4URLAndIdentity() {
        let server = LoomDiscovery.server(name: "Living Room", host: .init("10.0.0.5"), port: 8097)
        #expect(server.urlString == "http://10.0.0.5:8097")
        #expect(server.id == "Living Roomhttp://10.0.0.5:8097")
        #expect(Set([server, server]).count == 1)
    }

    @Test func resolvedIPv6URLIsBracketedAndScopeIsRemoved() {
        let server = LoomDiscovery.server(name: "Loom", host: .init("fe80::1%en0"), port: 8097)
        #expect(server.urlString == "http://[fe80::1]:8097")
    }

    @Test func hostnameURLRetainsHost() {
        let server = LoomDiscovery.server(name: "Loom", host: .init("loom.local"), port: 1234)
        #expect(server.urlString == "http://loom.local:1234")
    }
}
