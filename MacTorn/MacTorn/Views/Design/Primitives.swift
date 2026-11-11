import SwiftUI

// The pieces every screen is assembled from. See `Theme.swift` for the reasoning.

// MARK: - Page

/// A module's scrolling body: one column, sections separated by generous space.
struct BoardPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, Board.gutter)
            .padding(.top, 2)
            .padding(.bottom, Board.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Scrim

/// Full-panel backdrop behind a modal prompt: the one translucent thing in the app, and
/// opaque under Reduce Transparency.
struct BoardScrim: View {
    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        reduceTransparency ? Board.surface : Color.black.opacity(0.4)
    }
}

// MARK: - Section

/// A heading over a strong rule, then its rows. The rule is the only "container" a section
/// has: there is no card, fill or border around it.
struct BoardSection<Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Board.Space.s) {
                Text(title)
                    .font(.boardSection)
                    .foregroundStyle(Board.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Board.Space.s)
                trailing()
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
            }
            .padding(.bottom, 6)

            Board.ink.frame(height: 1)

            content()
        }
    }
}

extension BoardSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

extension BoardSection where Trailing == Text {
    /// A section with a short note on the right of its heading ("soonest first").
    init(_ title: String, note: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { Text(note) }, content: content)
    }
}

// MARK: - Rows

/// Anything laid out as a line in a section, closed by a hairline.
struct BoardRow<Content: View>: View {
    var verticalPadding: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            Board.hairline.frame(height: 1)
        }
    }
}

/// "Label …… value". The value is a numeral unless told otherwise.
struct ValueRow: View {
    let label: String
    let value: String
    var detail: String? = nil
    var tone: Board.Tone? = nil
    /// `false` for values that are words ("Scissors"), which should not be condensed.
    var isFigure = true

    var body: some View {
        BoardRow {
            HStack(alignment: .firstTextBaseline, spacing: Board.Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.boardBody)
                        .foregroundStyle(Board.ink)
                    if let detail {
                        Text(detail)
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Board.Space.s)
                Text(value)
                    .font(isFigure ? .figureValue : .boardBody)
                    .foregroundStyle(tone?.ink ?? Board.ink)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// One line of the board: a state rail, what it is, and how long until it happens.
/// A countdown that knows how far along it is draws that as a hairline under the row.
struct CountdownRow: View {
    let tone: Board.Tone
    let title: String
    var detail: String? = nil
    /// The countdown or state word, already formatted.
    let value: String
    /// 0…1 when the row can honestly say how far along it is; `nil` otherwise.
    var progress: Double? = nil

    private var valueColor: Color {
        switch tone {
        case .counting: return Board.ink
        case .ready, .alert, .idle: return tone.ink
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Board.Space.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.boardStrong)
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Board.Space.s)
                Text(value)
                    .font(.figureRow)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 13)
            .padding(.vertical, 8)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tone.fill)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }

            if let progress {
                ProgressLine(progress: progress, color: tone.fill, height: 2)
                    .padding(.leading, 13)
            } else {
                Board.hairline.frame(height: 1)
            }
        }
        // A ticking countdown must never animate its own layout.
        .transaction { $0.animation = nil }
    }
}

// MARK: - Meters

/// A flat progress line: the filled part in `color`, the rest in the track colour.
struct ProgressLine: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Board.track)
                if clamped > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geometry.size.width * clamped))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// One Torn bar on a single line: name, line, reading.
struct MeterReading: Identifiable {
    let name: String
    let current: Int
    let maximum: Int
    let color: Color

    var id: String { name }
    var progress: Double { NumericSafety.progress(current: current, maximum: maximum) }
}

/// The bars as aligned rows, so the lines share one left and one right edge whatever the
/// numbers. Each row is one accessibility element: the bar's name, then "51 of 150, 34
/// percent". (A `Grid` would align the columns for free, but modifiers on a `GridRow`
/// land on every cell, which made three elements per bar.)
struct MeterGrid: View {
    let meters: [MeterReading]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(meters) { meter in
                HStack(spacing: 10) {
                    // Every row lays out all the names and readings invisibly, so each
                    // column is as wide as its widest entry in any row.
                    ZStack(alignment: .leading) {
                        ForEach(meters) { name($0).hidden() }
                        name(meter)
                    }
                    ProgressLine(progress: meter.progress, color: meter.color)
                    ZStack(alignment: .trailing) {
                        ForEach(meters) { reading($0).hidden() }
                        reading(meter)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(meter.name)
                .accessibilityValue("\(meter.current) of \(meter.maximum), \(Int(meter.progress * 100)) percent")
            }
        }
    }

    private func name(_ meter: MeterReading) -> some View {
        Text(meter.name)
            .font(.boardBody)
            .foregroundStyle(Board.ink)
            .lineLimit(1)
            .fixedSize()
    }

    private func reading(_ meter: MeterReading) -> some View {
        (Text(TornFormatter.formatNumber(meter.current)).font(.figureValue).foregroundStyle(Board.ink)
         + Text(" / \(TornFormatter.formatNumber(meter.maximum))").font(.figure(16, weight: .regular))
            .foregroundStyle(Board.inkSecondary))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Small parts

struct StateDot: View {
    let tone: Board.Tone

    var body: some View {
        Circle()
            .fill(tone.fill)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// A number with its unit beside it: "2 messages".
struct CountLabel: View {
    let count: Int
    let noun: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(TornFormatter.formatNumber(count))
                .font(.figure(20))
                .foregroundStyle(Board.ink)
            Text(count == 1 ? noun : "\(noun)s")
                .font(.boardCaption)
                .foregroundStyle(Board.inkSecondary)
        }
    }
}

/// A line of state that needs saying in words: stale data, an error, a warning. Rail in the
/// state's colour, the message, and at most one way out.
struct BoardNotice<Action: View>: View {
    let tone: Board.Tone
    let message: String
    var detail: String? = nil
    /// UI-test identifier for the detail line, when a test needs to find the reason.
    var detailTestID: String? = nil
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Board.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.boardCaption.weight(.medium))
                    .foregroundStyle(tone.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.boardDetail)
                        .foregroundStyle(Board.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .uiTestID(detailTestID ?? "notice.detail")
                }
            }
            Spacer(minLength: Board.Space.s)
            action()
        }
        .padding(.leading, 13)
        .padding(.vertical, 2)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(tone.fill).frame(width: 3)
        }
    }
}

extension BoardNotice where Action == EmptyView {
    init(tone: Board.Tone, message: String, detail: String? = nil) {
        self.init(tone: tone, message: message, detail: detail, action: { EmptyView() })
    }
}

/// "Nothing here" said plainly, with what to do about it when there is something to do.
struct BoardEmptyState: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.boardStrong)
                .foregroundStyle(Board.ink)
            if let detail {
                Text(detail)
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Board.Space.m)
    }
}
