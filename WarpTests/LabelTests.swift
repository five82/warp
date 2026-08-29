import Foundation
import Testing
@testable import Warp

@Suite struct FormatTests {
    @Test func runtimeReadsLikeTheAndroidApp() {
        #expect(formatRuntime(118 * 60_000) == "1 h 58 m")
        #expect(formatRuntime(58 * 60_000) == "58 m")
        #expect(formatRuntime(2 * 3_600_000) == "2 h 0 m")
        #expect(formatRuntime(0) == "0 m")
    }

    @Test func runtimeFromSeconds() {
        #expect(formatRuntime(seconds: 1350) == "22 m")
        #expect(formatRuntime(seconds: 5_400) == "1 h 30 m")
    }

    @Test func clockDropsTheHourWhenThereIsNone() {
        #expect(formatClock(0) == "0:00")
        #expect(formatClock(75) == "1:15")
        #expect(formatClock(3_725) == "1:02:05")
    }

    @Test func timestampsParseWithAndWithoutFractionalSeconds() {
        #expect(parseTimestamp("2026-08-29T20:15:03Z") != nil)
        #expect(parseTimestamp("2026-08-29T20:15:03.482Z") != nil)
        #expect(parseTimestamp("nonsense") == nil)
    }

    /// Times are shown in the viewer's own zone, not the server's.
    @Test func timeOfDayFormatsForTheCouch() {
        let moment = try! #require(parseTimestamp("2026-08-29T20:15:00Z"))
        let utc = try! #require(TimeZone(identifier: "UTC"))
        #expect(formatTimeOfDay(moment, timeZone: utc, locale: Locale(identifier: "en_US")) == "8:15 PM")
    }
}

@Suite struct BannerLabelTests {
    /// An episode wears its show's name; the episode's own title is on the
    /// line beneath it.
    @Test func episodesLeadWithTheShow() {
        let episode = makeItem(
            id: 1, kind: "episode", title: "Diversity Day",
            season: 1, episode: 2, seriesTitle: "The Office"
        )
        #expect(programTitle(episode) == "The Office")
        #expect(programSubtitle(episode) == "S1E2 \u{00B7} Diversity Day")
    }

    @Test func doubleEpisodesShowTheRange() {
        let double = makeItem(id: 1, kind: "episode", title: "Finale", season: 9, episode: 24, episodeEnd: 25)
        #expect(episodeLabel(double) == "S9E24-25")
    }

    @Test func moviesLeadWithTheTitleAndYear() {
        let movie = makeItem(id: 2, kind: "movie", title: "Solaris", year: 1972)
        #expect(programTitle(movie) == "Solaris")
        #expect(programSubtitle(movie) == "1972")
    }

    /// Loom omits series_title for items listed inside their show hierarchy,
    /// which is how programs arrive on a show channel. The heading falls back
    /// to the episode's own title, and the subtitle stops repeating it.
    @Test func anEpisodeWithNoSeriesTitleFallsBackToItsOwn() {
        let orphan = makeItem(id: 3, kind: "episode", title: "Pilot", season: 1, episode: 1)
        #expect(programTitle(orphan) == "Pilot")
        #expect(programSubtitle(orphan) == "S1E1")
    }

    @Test func badgesReadResolutionThenRange() {
        #expect(videoBadges(VideoSummary(codec: "hevc", width: 3840, height: 2160, resolution: "4k", dynamicRange: "hdr")) == ["4K", "HDR"])
        #expect(videoBadges(VideoSummary(codec: "h264", width: 1920, height: 1080, resolution: "1080p", dynamicRange: "sdr")) == ["1080p"])
        #expect(videoBadges(VideoSummary(codec: "av1", width: 3840, height: 2160, resolution: "4k", dynamicRange: "dolby_vision")) == ["4K", "DV"])
    }

    @Test func sdrDetection() {
        #expect(VideoSummary(codec: "h264", width: 1920, height: 1080, resolution: "1080p", dynamicRange: "sdr").isSDR)
        #expect(VideoSummary(codec: "hevc", width: nil, height: nil, resolution: nil, dynamicRange: nil).isSDR)
        #expect(!VideoSummary(codec: "hevc", width: 3840, height: 2160, resolution: "4k", dynamicRange: "hdr").isSDR)
        #expect(!VideoSummary(codec: "av1", width: 3840, height: 2160, resolution: "4k", dynamicRange: "dolby_vision").isSDR)
        // No probed video stream at all.
        #expect(videoBadges(nil) == [])
    }

    @Test func theBlockTimesReadAsARange() {
        let start = try! #require(parseTimestamp("2026-08-29T20:00:00Z"))
        let program = makeProgram(id: 1, start: start, minutes: 45)
        let utc = try! #require(TimeZone(identifier: "UTC"))
        #expect(programTimeRange(program, timeZone: utc, locale: Locale(identifier: "en_US")) == "8:00 PM \u{2013} 8:45 PM")
    }
}
