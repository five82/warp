import Foundation
import Testing
@testable import Warp

@Suite struct ServerAddressTests {
    @Test func barehostGetsLoomsDefaultPort() {
        #expect(AppEnvironment.normalize("10.0.0.5")?.absoluteString == "http://10.0.0.5:8097")
        #expect(AppEnvironment.normalize(" 10.0.0.5 ")?.absoluteString == "http://10.0.0.5:8097")
    }

    @Test func anExplicitPortIsKept() {
        #expect(AppEnvironment.normalize("10.100.90.134:8098")?.absoluteString == "http://10.100.90.134:8098")
    }

    /// An https name is already whole; adding :8097 would break it.
    @Test func httpsNamesAreLeftAlone() {
        #expect(AppEnvironment.normalize("https://loom.example.ts.net")?.absoluteString == "https://loom.example.ts.net")
    }

    @Test func emptyIsNoServer() {
        #expect(AppEnvironment.normalize("") == nil)
        #expect(AppEnvironment.normalize("   ") == nil)
    }
}

@Suite struct LaunchOptionsTests {
    @Test func parsesTheDebugFlags() {
        let options = LaunchOptions.parse([
            "Warp", "-server", "http://10.100.90.134:8098", "-channel", "7", "-guide", "-freeze", "-surf", "12",
        ])
        #expect(options.server == "http://10.100.90.134:8098")
        #expect(options.channel == 7)
        #expect(options.guideOpen)
        #expect(options.frozenClock)
        #expect(options.surf == 12)
    }

    @Test func absentFlagsAreNil() {
        let options = LaunchOptions.parse(["Warp"])
        #expect(options.server == nil)
        #expect(options.channel == nil)
        #expect(!options.guideOpen)
        #expect(!options.frozenClock)
        #expect(options.surf == nil)
    }

    /// A flag at the very end has no value to take.
    @Test func aDanglingFlagIsIgnored() {
        #expect(LaunchOptions.parse(["Warp", "-channel"]).channel == nil)
    }
}
