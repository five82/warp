import Testing
@testable import Warp

@Suite struct PlaybackGateTests {
    @Test func blocksUltraHDAV1WithoutHardwareDecode() {
        #expect(PlaybackGate.blockReason(codec: "av1", width: 3840, height: 2160, av1HardwareDecode: false) != nil)
        // Scope crops sit under 2160 tall but well past 1920 wide.
        #expect(PlaybackGate.blockReason(codec: "av1", width: 3840, height: 1608, av1HardwareDecode: false) != nil)
        #expect(PlaybackGate.blockReason(codec: "AV1", width: 2560, height: 1440, av1HardwareDecode: false) != nil)
    }

    @Test func allows1080pAV1WithoutHardwareDecode() {
        #expect(PlaybackGate.blockReason(codec: "av1", width: 1920, height: 1080, av1HardwareDecode: false) == nil)
        #expect(PlaybackGate.blockReason(codec: "av1", width: 1280, height: 720, av1HardwareDecode: false) == nil)
    }

    @Test func allowsUltraHDAV1WithHardwareDecode() {
        #expect(PlaybackGate.blockReason(codec: "av1", width: 3840, height: 2160, av1HardwareDecode: true) == nil)
    }

    @Test func neverBlocksOtherCodecs() {
        #expect(PlaybackGate.blockReason(codec: "hevc", width: 3840, height: 2160, av1HardwareDecode: false) == nil)
        #expect(PlaybackGate.blockReason(codec: "h264", width: 3840, height: 2160, av1HardwareDecode: false) == nil)
        #expect(PlaybackGate.blockReason(codec: nil, width: 3840, height: 2160, av1HardwareDecode: false) == nil)
    }

    // Loom omits zero fields, so a stream can arrive with no dimensions at
    // all; an unknown size must not block.
    @Test func unknownDimensionsDoNotBlock() {
        #expect(PlaybackGate.blockReason(codec: "av1", width: nil, height: nil, av1HardwareDecode: false) == nil)
    }

    /// A program with no probed video stream is never blocked - Loom omits
    /// `video` entirely in that case.
    @Test func aProgramWithNoVideoSummaryIsNotBlocked() {
        #expect(PlaybackGate.blockReason(for: nil) == nil)
    }
}
