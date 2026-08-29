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

    /// Points per minute. A 22-minute episode is 176pt wide, a 2-hour film
    /// 960pt, so a row reads as time rather than as a list.
    private static let pointsPerMinute: CGFloat = 8
    // Ten channels plus the ruler and the header have to fit 1080 points
    // without scrolling vertically; the POC lineup is exactly ten.
    private static let rowHeight: CGFloat = 72
    private static let headerWidth: CGFloat = 300

    // Focus is per program cell; the guide opens on what is on now on the
    // current channel.
    @FocusState private var focusedProgram: Int64?

    var body: some View {
        ZStack {
            Color.stage.opacity(0.93).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(alignment: .top, spacing: 14) {
                    channelColumn
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 8) {
                            ruler
                            ForEach(lineup.channels) { channel in
                                row(for: channel)
                            }
                        }
                        .padding(.trailing, 60)
                    }
                    .scrollClipDisabled()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, TVLayout.sideMargin)
            .padding(.vertical, 40)
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
        VStack(alignment: .leading, spacing: 8) {
            // Lines up with the ruler above the first row. The width matters:
            // an unsized Color is horizontally flexible, and the HStack would
            // then split the screen between this column and the grid.
            Color.clear.frame(width: Self.headerWidth, height: 30)
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

    /// Half-hour ticks from the guide's origin.
    private var ruler: some View {
        HStack(spacing: 0) {
            ForEach(0..<48, id: \.self) { index in
                let moment = origin.addingTimeInterval(Double(index) * 1800)
                Text(formatTimeOfDay(moment))
                    .font(.labelSmall.monospacedDigit())
                    .foregroundStyle(Color.faint)
                    .frame(width: 30 * Self.pointsPerMinute, alignment: .leading)
            }
        }
        .frame(height: 30)
    }

    /// The grid starts at the current half hour so the columns line up with
    /// the ruler's ticks.
    private var origin: Date {
        let seconds = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 1800).rounded(.down) * 1800)
    }

    private func row(for channel: Channel) -> some View {
        let accent = channelThread(channel.key)
        let visible = channel.programs.filter { $0.endsAt > origin }
        return HStack(spacing: 6) {
            ForEach(visible) { program in
                Button {
                    onSelect(channel.number)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(programTitle(program.item))
                            .font(.titleSmall)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        if let subtitle = programSubtitle(program.item) {
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
        return max(CGFloat(minutes) * Self.pointsPerMinute, 120)
    }
}
