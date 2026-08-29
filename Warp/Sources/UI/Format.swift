import Foundation

// Text formatting, in the Takeup voice: "1 h 58 m", "S1E4", "8:15 PM".

func formatRuntime(_ milliseconds: Int64) -> String {
    let totalMinutes = Int(milliseconds / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours) h \(minutes) m" : "\(minutes) m"
}

func formatRuntime(seconds: Double) -> String {
    formatRuntime(Int64((seconds * 1000).rounded()))
}

func episodeLabel(_ item: Item) -> String? {
    guard let season = item.seasonNumber, let episode = item.episodeNumber else { return nil }
    if let end = item.episodeEndNumber, end > episode {
        return "S\(season)E\(episode)-\(end)"
    }
    return "S\(season)E\(episode)"
}

func formatClock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%d:%02d", minutes, secs)
}

/// A Loom RFC 3339 timestamp, with or without fractional seconds.
func parseTimestamp(_ iso: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return fractional.date(from: iso) ?? plain.date(from: iso)
}

/// "8:15 PM" in the viewer's own time zone - the guide's column headings and
/// the banner's block times.
func formatTimeOfDay(_ moment: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: moment)
}

// MARK: - Banner and guide labels

/// What the banner leads with: an episode wears its show's name, since the
/// episode's own title is on the line beneath it.
func programTitle(_ item: Item) -> String {
    if item.kind == "episode", let series = item.seriesTitle, !series.isEmpty {
        return series
    }
    return item.title
}

/// "S2E3 - Dinner Party" for an episode, the year for anything else. When the
/// heading above already is the episode's own title (Loom omits series_title
/// for items listed inside their show hierarchy), the title is not repeated.
func programSubtitle(_ item: Item) -> String? {
    if item.kind == "episode" {
        let label = episodeLabel(item)
        if programTitle(item) == item.title { return label }
        return [label, item.title].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
    if let year = item.year { return String(year) }
    return nil
}

/// A guide cell's heading. On a single-series channel the row label already
/// names the show, so the cell leads with the episode's own title instead of
/// repeating the series on every block.
func guideCellTitle(_ item: Item, singleSeries: Bool) -> String {
    singleSeries && item.kind == "episode" ? item.title : programTitle(item)
}

/// The line beneath: just "S16E3" on a single-series channel, since the
/// episode title is the heading there.
func guideCellSubtitle(_ item: Item, singleSeries: Bool) -> String? {
    singleSeries && item.kind == "episode" ? episodeLabel(item) : programSubtitle(item)
}

func resolutionBadge(_ resolution: String?) -> String? {
    switch resolution {
    case "4k": "4K"
    case "1080p": "1080p"
    case "720p": "720p"
    case "sd": "SD"
    default: nil
    }
}

func dynamicRangeBadge(_ dynamicRange: String?) -> String? {
    switch dynamicRange {
    case "hdr": "HDR"
    case "dolby_vision": "DV"
    default: nil
    }
}

/// The banner's technical badges, resolution first: ["4K", "HDR"].
func videoBadges(_ video: VideoSummary?) -> [String] {
    guard let video else { return [] }
    return [resolutionBadge(video.resolution), dynamicRangeBadge(video.dynamicRange)].compactMap { $0 }
}

/// "8:15 PM - 9:05 PM": the block a program occupies.
func programTimeRange(_ program: Program, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
    let start = formatTimeOfDay(program.startsAt, timeZone: timeZone, locale: locale)
    let end = formatTimeOfDay(program.endsAt, timeZone: timeZone, locale: locale)
    return "\(start) \u{2013} \(end)"
}

/// How far through the current block we are, 0...1.
func blockFraction(_ program: Program, at moment: Date) -> Double {
    let duration = program.durationSeconds
    guard duration > 0 else { return 0 }
    return min(max(program.offset(at: moment) / duration, 0), 1)
}
