import Foundation
@testable import Warp

/// Item's memberwise init spans every field; tests only vary these few.
func makeItem(
    id: Int64,
    kind: String = "episode",
    title: String = "Item",
    year: Int? = nil,
    season: Int? = nil,
    episode: Int? = nil,
    episodeEnd: Int? = nil,
    seriesTitle: String? = nil,
    durationMs: Int64? = nil
) -> Item {
    Item(
        id: id, libraryId: nil, parentId: nil, kind: kind, title: title,
        sortTitle: nil, year: year, seasonNumber: season, episodeNumber: episode,
        episodeEndNumber: episodeEnd, overview: nil, tagline: nil, genres: nil,
        contentRating: nil, posterImageId: nil, posterImageTag: nil,
        backdropImageId: nil, backdropImageTag: nil, logoImageId: nil,
        logoImageTag: nil, thumbImageId: nil, thumbImageTag: nil,
        durationMs: durationMs, media: nil, seriesTitle: seriesTitle, seasonTitle: nil
    )
}

func makeProgram(
    id: Int64,
    start: Date,
    minutes: Double,
    item: Item? = nil,
    video: VideoSummary? = nil,
    streamUrl: String? = "/api/v1/media/1?tag=abc"
) -> Program {
    Program(
        id: id,
        startsAt: start,
        endsAt: start.addingTimeInterval(minutes * 60),
        item: item ?? makeItem(id: id),
        video: video,
        streamUrl: streamUrl
    )
}

/// Back-to-back programs of equal length, the way Loom schedules them.
func makeChannel(
    id: Int64 = 1,
    number: Int = 1,
    key: String = "show:1",
    name: String = "Channel",
    kind: String = "show",
    from start: Date,
    blocks: Int = 4,
    minutes: Double = 30,
    firstProgramId: Int64 = 100
) -> Channel {
    var programs: [Program] = []
    for index in 0..<blocks {
        programs.append(makeProgram(
            id: firstProgramId + Int64(index),
            start: start.addingTimeInterval(Double(index) * minutes * 60),
            minutes: minutes
        ))
    }
    return Channel(id: id, number: number, key: key, name: name, kind: kind, programs: programs)
}

/// The client's decoder configuration, for decoding fixtures the same way.
func loomDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}
