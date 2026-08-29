import SwiftUI

/// The guide: rows are channels, columns are time, cells are programs. It
/// overlays the still-playing video. Select tunes to a row's channel (a fake
/// channel only ever plays "now", so picking a future block still just means
/// "go to this channel"); Menu closes.
///
/// Focus is per row, not per cell. tvOS's focus engine moves by geometry, so
/// with cells of every width Up from a narrow cell landed wherever the row
/// above overlapped it most, and correcting that after the fact fought the
/// engine (it moved, then the app moved again). A row is full width, so
/// Up/Down have exactly one candidate; the column is app state: Left/Right
/// step the highlighted cell, and a vertical run holds its time column.
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
    /// The guide is a full-screen grid, so it hugs the safe area (already
    /// 90 pt sides and 60 pt top/bottom on tvOS) rather than adding the
    /// banner's `TVLayout.sideMargin` on top of it.
    private static let horizontalMargin: CGFloat = 16
    private static let verticalMargin: CGFloat = 12
    private static let rowSpacing: CGFloat = 8
    private static let headerWidth: CGFloat = 380
    private static let columnSpacing: CGFloat = 14
    private static let rulerHeight: CGFloat = 30
    private static let cellSpacing: CGFloat = 6
    /// The program on now is clipped to what is left of it; keep enough of
    /// it to read a title.
    private static let minimumCellWidth: CGFloat = 160

    @FocusState private var focusedChannel: Int64?
    /// The highlighted cell in the focused row.
    @State private var selectedProgram: Int64?
    /// The time column a vertical run of Up/Down holds to, like a cursor
    /// keeping its x while it moves between lines. Left/Right reset it to
    /// the cell they land on.
    @State private var columnAnchor: Date
    /// How far the grid is scrolled to the right, in points. Plain state, not
    /// a ScrollView: a horizontal ScrollView here gets scrolled to its far
    /// end by the focus engine hunting for focusable content whenever a
    /// press has no candidate in the grid (Up from the top row, say), even
    /// with scrolling disabled. The ruler shares it so the ticks stay over
    /// their columns.
    @State private var gridOffset: CGFloat = 0
    /// The grid's left edge: the moment the guide opened (section 4.2,
    /// "columns = time from now"). Starting at the top of the half hour put
    /// the program that had just ended at the left edge, where the eye reads
    /// "now", and the one actually playing looked like "next up". Fixed for
    /// the guide's lifetime so cells do not creep while you browse.
    @State private var origin: Date

    init(lineup: Lineup, currentNumber: Int, now: Date, onSelect: @escaping (Int) -> Void, onSettings: @escaping () -> Void) {
        self.lineup = lineup
        self.currentNumber = currentNumber
        self.now = now
        self.onSelect = onSelect
        self.onSettings = onSettings
        _origin = State(initialValue: now)
        _columnAnchor = State(initialValue: now)
    }

    var body: some View {
        ZStack {
            Color.stage.opacity(0.93).ignoresSafeArea()
            // The ruler and the rows are 24 hours wide; every container they
            // sit in needs an explicit width or their ideal width blows the
            // layout out to 23,000 points, so measure the screen once and
            // hand the widths down.
            GeometryReader { geometry in
                let width = geometry.size.width - 2 * Self.horizontalMargin
                let gridWidth = width - Self.headerWidth - Self.columnSpacing
                VStack(alignment: .leading, spacing: 10) {
                    header
                    HStack(spacing: Self.columnSpacing) {
                        Color.clear.frame(width: Self.headerWidth, height: Self.rulerHeight)
                        ruler(width: gridWidth)
                    }
                    ScrollView(.vertical) {
                        // The focus targets are a layer of invisible,
                        // viewport-wide buttons over the grid, one per row,
                        // outside the horizontal scroll view. Nothing inside
                        // that scroll view is focusable: a focused row 24
                        // hours wide made the engine "scroll it into view",
                        // flinging the grid sideways and off its rows.
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .top, spacing: Self.columnSpacing) {
                                channelColumn
                                grid(width: gridWidth)
                            }
                            focusLayer(width: width)
                        }
                        // Room for the highlight on the first and last rows.
                        .padding(.vertical, 4)
                    }
                }
                .frame(width: width)
                .padding(.horizontal, Self.horizontalMargin)
                .padding(.vertical, Self.verticalMargin)
            }
        }
        .onAppear {
            focusedChannel = (lineup.channel(number: currentNumber) ?? lineup.channels.first)?.id
        }
        // A row gained focus (Up/Down, or the opening): highlight the cell
        // under the held time column.
        .onChange(of: focusedChannel, initial: true) { _, id in
            guard let channel = lineup.channels.first(where: { $0.id == id }) else { return }
            selectedProgram = cell(in: channel, near: columnAnchor)?.id
        }
        // Keep the highlighted cell in view.
        .onChange(of: selectedProgram, initial: true) { _, id in
            guard gridWidth > 0, let id, let channel = lineup.channels.first(where: { $0.id == focusedChannel }),
                  let cell = placedCells(of: channel).first(where: { $0.program.id == id })
            else { return }
            let target: CGFloat
            if cell.x < gridOffset || cell.width > gridWidth {
                // Off the left, or a movie wider than the window: the title
                // is at the leading edge, so that is the edge to show.
                target = cell.x
            } else if cell.x + cell.width > gridOffset + gridWidth {
                target = cell.x + cell.width - gridWidth
            } else {
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { gridOffset = max(0, target) }
        }
    }

    /// The grid's viewport width, measured by the GeometryReader.
    @State private var gridWidth: CGFloat = 0

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
    /// never scrolls away. Under the name is what the channel is playing:
    /// programs do not start on the half hour, so the first cell in the
    /// grid is often too narrow to read.
    private var channelColumn: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(lineup.channels) { channel in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(String(channel.number))
                        .font(.titleMedium.monospacedDigit())
                        .foregroundStyle(channelThread(channel.key))
                        .frame(width: 54, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .font(.titleSmall)
                            .foregroundStyle(channel.number == currentNumber ? Color.ink : Color.muted)
                            .lineLimit(1)
                        if let program = channel.programs.last(where: { $0.contains(origin) }) {
                            Text(guideCellTitle(program.item, singleSeries: channel.isSingleSeries))
                                .font(.bodySmall)
                                .foregroundStyle(Color.faint)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: Self.headerWidth, height: Self.rowHeight, alignment: .leading)
            }
        }
        .frame(width: Self.headerWidth)
    }

    /// Half-hour ticks at their true positions from the origin, shifted to
    /// follow the grid.
    private func ruler(width: CGFloat) -> some View {
        let seconds = origin.timeIntervalSinceReferenceDate
        let firstTick = Date(timeIntervalSinceReferenceDate: (seconds / 1800).rounded(.up) * 1800)
        let lead = CGFloat(firstTick.timeIntervalSince(origin) / 60) * Self.pointsPerMinute
        return HStack(spacing: 0) {
            ForEach(0..<48, id: \.self) { index in
                let moment = firstTick.addingTimeInterval(Double(index) * 1800)
                Text(formatTimeOfDay(moment))
                    .font(.labelSmall.monospacedDigit())
                    .foregroundStyle(Color.faint)
                    .frame(width: 30 * Self.pointsPerMinute, alignment: .leading)
            }
        }
        .padding(.leading, lead)
        .offset(x: -gridOffset)
        .frame(width: width, height: Self.rulerHeight, alignment: .leading)
        .clipped()
    }

    /// The program cells: content only, nothing focusable. Each row renders
    /// just the cells inside the window (plus a viewport either side, so a
    /// scroll animation has something to slide in), placed by `gridOffset`.
    private func grid(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            ForEach(lineup.channels) { channel in
                row(for: channel, width: width)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .onAppear { gridWidth = width }
        .onChange(of: width) { _, width in gridWidth = width }
    }

    /// One row of cells; the highlighted one is `selectedProgram` while the
    /// row has focus.
    private func row(for channel: Channel, width: CGFloat) -> some View {
        let accent = channelThread(channel.key)
        let singleSeries = channel.isSingleSeries
        let focused = focusedChannel == channel.id
        let window = (gridOffset - width)...(gridOffset + 2 * width)
        let shown = placedCells(of: channel).filter { window.contains($0.x) || window.contains($0.x + $0.width) }
        return HStack(spacing: Self.cellSpacing) {
            ForEach(shown, id: \.program.id) { cell in
                GuideCell(
                    title: guideCellTitle(cell.program.item, singleSeries: singleSeries),
                    subtitle: guideCellSubtitle(cell.program.item, singleSeries: singleSeries),
                    accent: accent,
                    highlighted: focused && selectedProgram == cell.program.id
                )
                .frame(width: cell.width, height: Self.rowHeight)
            }
        }
        // The margin keeps the highlight of the first column inside the clip.
        .padding(.leading, (shown.first?.x ?? 0) - gridOffset + 4)
        .frame(width: width, height: Self.rowHeight, alignment: .leading)
    }

    private struct PlacedCell {
        let program: Program
        let x: CGFloat
        let width: CGFloat
    }

    /// The row's cells laid end to end from the origin.
    private func placedCells(of channel: Channel) -> [PlacedCell] {
        var x: CGFloat = 0
        return visiblePrograms(of: channel).map { program in
            let width = width(of: program)
            defer { x += width + Self.cellSpacing }
            return PlacedCell(program: program, x: x, width: width)
        }
    }

    /// The focus targets: an invisible button the width of the viewport
    /// over each row. Up/Down are the engine's (the rows are full width, so
    /// the target is never in doubt) and the column follows in onChange;
    /// Left/Right have no focusable neighbour, so they come here.
    private func focusLayer(width: CGFloat) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(lineup.channels) { channel in
                Button {
                    onSelect(channel.number)
                } label: {
                    Color.clear
                        .frame(width: width, height: Self.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(TVInvisibleButtonStyle())
                .focused($focusedChannel, equals: channel.id)
                .onMoveCommand { direction in
                    step(direction, in: channel)
                }
            }
        }
    }

    private func step(_ direction: MoveCommandDirection, in channel: Channel) {
        let visible = visiblePrograms(of: channel)
        guard let index = visible.firstIndex(where: { $0.id == selectedProgram }) else { return }
        let target: Int
        switch direction {
        case .left: target = index - 1
        case .right: target = index + 1
        default: return
        }
        guard visible.indices.contains(target) else { return }
        let program = visible[target]
        selectedProgram = program.id
        columnAnchor = max(program.startsAt, origin)
    }

    private func visiblePrograms(of channel: Channel) -> [Program] {
        channel.programs.filter { $0.endsAt > origin }
    }

    /// The cell in `channel`'s row under the time column `moment`: the program
    /// on then, else the nearest edge of the row.
    private func cell(in channel: Channel, near moment: Date) -> Program? {
        let visible = visiblePrograms(of: channel)
        if let on = visible.last(where: { $0.contains(moment) }) { return on }
        if let first = visible.first, moment < first.startsAt { return first }
        return visible.last
    }

    /// The program on now is clipped to what is left of it; the rest run
    /// their full length.
    private func width(of program: Program) -> CGFloat {
        let start = max(program.startsAt, origin)
        let minutes = program.endsAt.timeIntervalSince(start) / 60
        return max(CGFloat(minutes) * Self.pointsPerMinute, Self.minimumCellWidth)
    }
}

/// A program block in the grid. Not focusable: the row is, and it tells the
/// cell whether it is the highlighted column.
private struct GuideCell: View {
    let title: String
    let subtitle: String?
    let accent: Color
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.titleSmall)
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.bodySmall)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            highlighted ? accent.opacity(0.32) : Color.surface1.opacity(0.85),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(highlighted ? accent : Color.line, lineWidth: highlighted ? 3 : 1)
        )
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }
}
