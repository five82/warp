import Foundation
import Testing
@testable import Warp

@Suite struct LineupDecodingTests {
    /// One channel with one program, exactly the shape of the 3.3 contract.
    static let json = """
    {
      "now": "2026-08-29T20:15:03Z",
      "items": [
        {
          "id": 3,
          "number": 3,
          "key": "show:2316",
          "name": "The Office",
          "programs": [
            {
              "id": 9812,
              "starts_at": "2026-08-29T19:58:10Z",
              "ends_at": "2026-08-29T20:20:40Z",
              "item": {
                "id": 2317,
                "kind": "episode",
                "title": "Diversity Day",
                "season_number": 1,
                "episode_number": 2,
                "series_title": "The Office",
                "duration_ms": 1350000
              },
              "video": {
                "codec": "hevc", "width": 1920, "height": 1080,
                "resolution": "1080p", "dynamic_range": "sdr"
              },
              "stream_url": "/api/v1/media/812?tag=deadbeef"
            }
          ]
        }
      ]
    }
    """

    @Test func decodesTheContractShape() throws {
        let lineup = try loomDecoder().decode(Lineup.self, from: Data(Self.json.utf8))
        #expect(lineup.now == parseTimestamp("2026-08-29T20:15:03Z"))
        #expect(lineup.channels.count == 1)
        let channel = try #require(lineup.channels.first)
        #expect(channel.number == 3)
        #expect(channel.key == "show:2316")
        let program = try #require(channel.programs.first)
        #expect(program.id == 9812)
        #expect(program.item.title == "Diversity Day")
        #expect(program.item.seriesTitle == "The Office")
        #expect(program.video?.dynamicRange == "sdr")
        #expect(program.streamUrl == "/api/v1/media/812?tag=deadbeef")
        // 19:58:10 -> 20:20:40 is 22.5 minutes.
        #expect(program.durationSeconds == 1350)
    }

    /// Go marshals nil slices as null; every list wrapper has to tolerate it.
    @Test func tolerionsNullAndEmptyLists() throws {
        let nulls = """
        {"now": "2026-08-29T20:15:03Z", "items": null}
        """
        #expect(try loomDecoder().decode(Lineup.self, from: Data(nulls.utf8)).channels.isEmpty)

        let empty = """
        {"now": "2026-08-29T20:15:03Z", "items": []}
        """
        #expect(try loomDecoder().decode(Lineup.self, from: Data(empty.utf8)).channels.isEmpty)

        let nullPrograms = """
        {"now": "2026-08-29T20:15:03Z", "items": [
          {"id": 1, "number": 1, "key": "mix", "name": "Mix", "programs": null}
        ]}
        """
        let lineup = try loomDecoder().decode(Lineup.self, from: Data(nullPrograms.utf8))
        #expect(lineup.channels.first?.programs.isEmpty == true)
    }

    /// `video` is omitted when the file has no probed video stream, and
    /// `stream_url` when the file is gone.
    @Test func optionalProgramFieldsMayBeAbsent() throws {
        let json = """
        {"now": "2026-08-29T20:15:03Z", "items": [
          {"id": 1, "number": 1, "key": "mix", "name": "Mix", "programs": [
            {"id": 5, "starts_at": "2026-08-29T20:00:00Z", "ends_at": "2026-08-29T21:00:00Z",
             "item": {"id": 9, "kind": "movie", "title": "Solaris"}}
          ]}
        ]}
        """
        let program = try #require(
            try loomDecoder().decode(Lineup.self, from: Data(json.utf8)).channels.first?.programs.first
        )
        #expect(program.video == nil)
        #expect(program.streamUrl == nil)
    }

    @Test func rejectsUnparseableTimestamps() {
        let json = """
        {"now": "not a time", "items": []}
        """
        #expect(throws: (any Error).self) {
            try loomDecoder().decode(Lineup.self, from: Data(json.utf8))
        }
    }
}
