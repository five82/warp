import Foundation
import Testing
@testable import Warp

struct CaptionsTests {
    @Test func defaultsOffAndRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "CaptionsTests.\(UUID().uuidString)"))
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        #expect(Captions.load(from: defaults).enabled == false)
        Captions(enabled: true).store(in: defaults)
        #expect(Captions.load(from: defaults).enabled == true)
        Captions(enabled: false).store(in: defaults)
        #expect(Captions.load(from: defaults).enabled == false)
    }
}
