import SwiftUI

/// The guide: rows are channels, columns are time, cells are programs. It
/// overlays the still-playing video. Select tunes to a row's channel (a fake
/// channel only ever plays "now", so picking a future block still just means
/// "go to this channel"); Menu closes.
struct GuideView: View {
    let lineup: Lineup
    let currentNumber: Int
    let now: Date
    let onSelect: (Int) -> Void
    let onSettings: () -> Void

    /// Points per minute. A 22-minute episode is 352pt wide, enough for its
    /// title and "S16E3 · Episode Name" on the second line; the grid shows
    /// about 90 minutes at a time, the window a cable guide uses.
    private static let pointsPerMinute: CGFloat = 16
    // The lineup no longer fits 1080 points, so the rows scroll vertically
    // (the ruler stays put above them).
    private static let rowHeight: CGFloat = 84
    private static let rowSpacing: CGFloat = 8
    private static let headerWidth: CGFloat = 300
    private static let columnSpacing: CGFloat = 14
    private static let rulerHeight: CGFloat = 30
    /// The first visible program is clipped by the origin; keep enough of it
    /// to read a title.
    private static let minimumCellWidth: CGFloat = 160

    // Focus is per program cell; the guide opens on what is on now on the
    // current channel.
    @FocusState private var focusedProgram: Int64?
    /// The grid's horizontal scroll offset, mirrored onto the ruler so the
    /// ticks stay over their columns while the rows scroll both ways.
    @State private var gridOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.stage.opacity(0.93).ignoresSafeArea()
            // The ruler and the rows are 24 hours wide; every container they
            // sit in needs an explicit width or their ideal width blows the
            // layout out to 23,000 points, so measure the screen once and
            // hand the widths down.
            GeometryReader { geometry in
                let width = geometry.size.width - 2 * TVLayout.sideMargin
                let gridWidth = width - Self.headerWidth - Self.columnSpacing
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack(spacing: Self.columnSpacing) {
                        Color.clear.frame(width: Self.headerWidth, height: Self.rulerHeight)
                        ruler(width: gridWidth)
                    }
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: Self.columnSpacing) {
                            channelColumn
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                                    ForEach(lineup.channels) { channel in
                                        row(for: channel)
                                    }
                                }
                                .padding(.trailing, 60)
                            }
                            // Clipped, or cells scrolled off the left draw
                            // over the channel column; the margin keeps the
                            // focus ring of the first column inside the clip.
                            .contentMargins(.leading, 4)
                            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                                geometry.contentOffset.x
                            } action: { _, offset in
                                gridOffset = offset
                            }
                            .frame(width: gridWidth)
                        }
                        // Room for the focus ring on the first and last rows.
                        .padding(.vertical, 4)
                    }
                }
                .frame(width: width)
                .padding(.horizontal, TVLayout.sideMargin)
                .padding(.vertical, 40)
            }
        }
        .onAppear {
            focusedProgram = lineup.channel(number: currentNumber)?.program(at: now)?.id
                ?? lineup.channels.first?.programs.first?.id
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                RowLabel(text: "Guide", color: .muted)
                Text(formatTimeOfDay(now))
                    .font(.titleMedium.monospacedDigit())
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Button("Server", action: onSettings)
                .buttonStyle(TVPillButtonStyle())
        }
    }

    /// Fixed row headings beside the scrolling grid, so a channel's identity
    /// never scrolls away.
    private var channelColumn: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(lineup.channels) { channel in
                HStack(spacing: 16) {
                    Text(String(channel.number))
                        .font(.titleMedium.monospacedDigit())
                        .foregroundStyle(channelThread(channel.key))
                        .frame(width: 54, alignment: .trailing)
                    Text(channel.name)
                        .font(.titleSmall)
                        .foregroundStyle(channel.number == currentNumber ? Color.ink : Color.muted)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(width: Self.headerWidth, height: Self.rowHeight, alignment: .leading)
            }
        }
        .frame(width: Self.headerWidth)
    }

    /// Half-hour ticks from the guide's origin, shifted to follow the grid.
    private func ruler(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<48, id: \.self) { index in
                let moment = origin.addingTimeInterval(Double(index) * 1800)
                Text(formatTimeOfDay(moment))
                    .font(.labelSmall.monospacedDigit())
                    .foregroundStyle(Color.faint)
                    .frame(width: 30 * Self.pointsPerMinute, alignment: .leading)
            }
        }
        .offset(x: -gridOffset)
        .frame(width: width, height: Self.rulerHeight, alignment: .leading)
        .clipped()
    }

    /// The grid starts at the current half hour so the columns line up with
    /// the ruler's ticks.
    private var origin: Date {
        let seconds = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 1800).rounded(.down) * 1800)
    }

    private func row(for channel: Channel) -> some View {
        let accent = channelThread(channel.key)
        let singleSeries = channel.isSingleSeries
        let visible = channel.programs.filter { $0.endsAt > origin }
        return HStack(spacing: 6) {
            ForEach(visible) { program in
                Button {
                    onSelect(channel.number)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guideCellTitle(program.item, singleSeries: singleSeries))
                            .font(.titleSmall)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        if let subtitle = guideCellSubtitle(program.item, singleSeries: singleSeries) {
                            Text(subtitle)
                                .font(.bodySmall)
                                .foregroundStyle(Color.muted)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(TVGuideCellStyle(accent: accent))
                .frame(width: width(of: program), height: Self.rowHeight)
                .focused($focusedProgram, equals: program.id)
            }
        }
    }

    /// The first visible program is clipped by the origin; the rest run their
    /// full length.
    private func width(of program: Program) -> CGFloat {
        let start = max(program.startsAt, origin)
        let minutes = program.endsAt.timeIntervalSince(start) / 60
        return max(CGFloat(minutes) * Self.pointsPerMinute, Self.minimumCellWidth)
    }
}
