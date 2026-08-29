import Foundation

// Models mirroring Loom's /api/v1 JSON, copied from Takeup and trimmed to what
// Warp reads, plus the channels DTOs from the lineup contract. The server omits
// empty/zero fields, so everything but identity is optional. Decoded with
// .convertFromSnakeCase.

struct Item: Codable, Identifiable, Hashable {
    let id: Int64
    let libraryId: Int64?
    let parentId: Int64?
    let kind: String
    let title: String
    let sortTitle: String?
    let year: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeEndNumber: Int?
    let overview: String?
    let tagline: String?
    let genres: [Genre]?
    let contentRating: String?
    let posterImageId: Int64?
    let posterImageTag: String?
    let backdropImageId: Int64?
    let backdropImageTag: String?
    let logoImageId: Int64?
    let logoImageTag: String?
    let thumbImageId: Int64?
    let thumbImageTag: String?
    let durationMs: Int64?
    let media: MediaFile?
    // Context for episodes listed outside their show hierarchy.
    let seriesTitle: String?
    let seasonTitle: String?
}

struct Genre: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let itemCount: Int?
}

struct MediaFile: Codable, Hashable {
    let id: Int64
    let itemId: Int64?
    let filename: String?
    let size: Int64?
    let tag: String?
    let durationMs: Int64?
    let container: String?
    let probeError: String?
    let streams: [Stream]?
    let chapters: [Chapter]?
}

struct Stream: Codable, Hashable {
    let index: Int
    let kind: String
    let codec: String?
    let profile: String?
    let language: String?
    let title: String?
    let width: Int?
    let height: Int?
    let resolution: String?
    let channels: Int?
    let channelLayout: String?
    let dynamicRange: String?
    let isDefault: Bool?
    let isForced: Bool?
}

struct Chapter: Codable, Hashable {
    let index: Int
    let startMs: Int64?
    let title: String?
}

struct Library: Codable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let name: String
    let itemCount: Int64?
}

// MARK: - Channels (docs/proposal.md 3.3)

/// The first video stream of a program's file, flattened by Loom so the client
/// never has to open the media file to gate or badge a program. Omitted
/// entirely when the file has no probed video stream.
struct VideoSummary: Codable, Hashable {
    let codec: String?
    let width: Int?
    let height: Int?
    let resolution: String?
    let dynamicRange: String?
}

/// One scheduled block on a channel.
struct Program: Codable, Identifiable, Hashable {
    let id: Int64
    let startsAt: Date
    let endsAt: Date
    let item: Item
    let video: VideoSummary?
    /// Server-relative media path, already stat-checked by Loom. Absent when
    /// the file went missing between the scan and the request.
    let streamUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id, startsAt, endsAt, item, video, streamUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        // Timestamps arrive as RFC 3339 strings; parsing them here keeps the
        // shared decoder's date strategy out of Item's plain string fields.
        let start = try container.decode(String.self, forKey: .startsAt)
        let end = try container.decode(String.self, forKey: .endsAt)
        guard let startsAt = parseTimestamp(start), let endsAt = parseTimestamp(end) else {
            throw DecodingError.dataCorruptedError(
                forKey: .startsAt, in: container, debugDescription: "unparseable program timestamps"
            )
        }
        self.startsAt = startsAt
        self.endsAt = endsAt
        item = try container.decode(Item.self, forKey: .item)
        video = try container.decodeIfPresent(VideoSummary.self, forKey: .video)
        streamUrl = try container.decodeIfPresent(String.self, forKey: .streamUrl)
    }

    init(id: Int64, startsAt: Date, endsAt: Date, item: Item, video: VideoSummary?, streamUrl: String?) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.item = item
        self.video = video
        self.streamUrl = streamUrl
    }

    var durationSeconds: Double { endsAt.timeIntervalSince(startsAt) }

    /// How far into this block `moment` lands, clamped to the block.
    func offset(at moment: Date) -> Double {
        min(max(moment.timeIntervalSince(startsAt), 0), max(durationSeconds, 0))
    }

    func contains(_ moment: Date) -> Bool {
        moment >= startsAt && moment < endsAt
    }
}

struct Channel: Codable, Identifiable, Hashable {
    let id: Int64
    /// Stable 1-based channel number; Loom never reuses or reshuffles them.
    let number: Int
    let key: String
    let name: String
    let kind: String
    let programs: [Program]

    private enum CodingKeys: String, CodingKey {
        case id, number, key, name, kind, programs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        key = try container.decode(String.self, forKey: .key)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(String.self, forKey: .kind)
        // The contract promises [] rather than null, but Go marshals nil
        // slices as null and every other Loom list wrapper tolerates it.
        programs = try container.decodeIfPresent([Program].self, forKey: .programs) ?? []
    }

    init(id: Int64, number: Int, key: String, name: String, kind: String, programs: [Program]) {
        self.id = id
        self.number = number
        self.key = key
        self.name = name
        self.kind = kind
        self.programs = programs
    }

    /// What is on at `moment`, or nil if the schedule has a hole there.
    func program(at moment: Date) -> Program? {
        programs.last { $0.contains(moment) }
    }

    /// The block that follows `program` on this channel.
    func program(after program: Program) -> Program? {
        guard let index = programs.firstIndex(where: { $0.id == program.id }) else { return nil }
        let next = programs.index(after: index)
        return next < programs.endIndex ? programs[next] : nil
    }
}

/// The whole `/channels` response: the server clock plus every channel's
/// schedule through the horizon.
struct Lineup: Codable {
    let now: Date
    let channels: [Channel]

    private enum CodingKeys: String, CodingKey {
        case now
        case channels = "items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stamp = try container.decode(String.self, forKey: .now)
        guard let now = parseTimestamp(stamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .now, in: container, debugDescription: "unparseable server clock"
            )
        }
        self.now = now
        channels = try container.decodeIfPresent([Channel].self, forKey: .channels) ?? []
    }

    init(now: Date, channels: [Channel]) {
        self.now = now
        self.channels = channels
    }

    var numbers: [Int] { channels.map(\.number).sorted() }

    func channel(number: Int) -> Channel? {
        channels.first { $0.number == number }
    }

    /// Channel numbers are not dense (Loom never renumbers), so stepping walks
    /// the sorted list rather than doing arithmetic on the number itself.
    func number(from current: Int, steppingBy delta: Int) -> Int? {
        Self.number(from: current, steppingBy: delta, in: numbers)
    }

    static func number(from current: Int, steppingBy delta: Int, in numbers: [Int]) -> Int? {
        guard !numbers.isEmpty else { return nil }
        // An unknown current number (a channel that vanished from the lineup)
        // steps from where it would have sat.
        let index = numbers.firstIndex(of: current) ?? numbers.firstIndex { $0 > current } ?? 0
        let count = numbers.count
        let stepped = ((index + delta) % count + count) % count
        return numbers[stepped]
    }
}

/// Loom marshals empty lists as `"items": null`, so every list wrapper decodes
/// null as empty.
struct ItemsPage: Codable {
    let items: [Item]
    let limit: Int?
    let offset: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
    }
}
