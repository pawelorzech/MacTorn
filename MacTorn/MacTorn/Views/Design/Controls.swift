import SwiftUI

// Controls of the dispatch board. Native switches, pickers and steppers are used as they
// are; these are the ones the system has no quiet-enough version of.

// MARK: - Buttons

/// The one button shape in the app: 30 pt tall, 7 pt corners, a label and nothing else.
struct BoardButtonStyle: ButtonStyle {
    enum Kind {
        /// Outlined, for most actions and every "open this in Torn" link.
        case standard
        /// Filled with the accent: the single main action of a screen.
        case primary
        /// Carries a state: "this is ready, act on it".
        case tone(Board.Tone)
        /// Text only, for a way out inside a line of text ("Retry").
        case inline
    }

    var kind: Kind = .standard
    /// Stretch to the width offered, for buttons laid out in a row of equals.
    var fillsWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.boardCaption.weight(.medium))
            .lineLimit(1)

        Group {
            switch kind {
            case .inline:
                label.foregroundStyle(Board.accent)
            case .standard, .primary, .tone:
                label
                    .foregroundStyle(foreground)
                    .padding(.horizontal, fillsWidth ? 6 : 10)
                    .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 30)
                    .background(background, in: RoundedRectangle(cornerRadius: Board.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: Board.Radius.control)
                            .strokeBorder(outline, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Board.Radius.control))
            }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
    }

    private var foreground: Color {
        switch kind {
        case .standard, .inline: return Board.ink
        case .primary: return Board.onAccent
        case .tone(let tone): return tone.ink
        }
    }

    private var background: Color {
        switch kind {
        case .standard, .inline: return .clear
        case .primary: return Board.accent
        case .tone(let tone): return tone.wash
        }
    }

    private var outline: Color {
        switch kind {
        case .standard, .inline: return Board.outline
        case .primary: return Board.accent
        case .tone(let tone): return tone.outline
        }
    }
}

extension ButtonStyle where Self == BoardButtonStyle {
    static var board: BoardButtonStyle { BoardButtonStyle() }
    static var boardFill: BoardButtonStyle { BoardButtonStyle(fillsWidth: true) }
    static var boardPrimary: BoardButtonStyle { BoardButtonStyle(kind: .primary) }
    static var boardInline: BoardButtonStyle { BoardButtonStyle(kind: .inline) }
    static func board(_ tone: Board.Tone, fillsWidth: Bool = true) -> BoardButtonStyle {
        BoardButtonStyle(kind: .tone(tone), fillsWidth: fillsWidth)
    }
}

/// A row of "open this page in Torn" buttons that wraps as needed.
struct TornLinks: View {
    struct Link: Identifiable {
        let title: String
        let url: URL
        var id: String { title }
    }

    let links: [Link]
    var columns = 3

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns),
            spacing: 6
        ) {
            ForEach(links) { link in
                Button(link.title) { BrowserManager.shared.open(link.url) }
                    .buttonStyle(.boardFill)
                    .accessibilityHint("Opens Torn in your browser")
            }
        }
    }
}

/// A square, borderless icon button with a real hit area: refresh, remove, close.
struct IconButton: View {
    let systemImage: String
    let label: String
    var tone: Board.Tone = .idle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tone.ink)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Choice chips

/// An on/off choice among a few peers ("alert me 1 min before"). On is the accent, filled.
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.boardCaption.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isOn ? Board.onAccent : Board.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(isOn ? Board.accent : Color.clear, in: RoundedRectangle(cornerRadius: Board.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Board.Radius.control)
                        .strokeBorder(isOn ? Board.accent : Board.outline, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Board.Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
    }
}

// MARK: - Fields and settings rows

/// A text field sunk into the surface, the same height as a button.
struct BoardFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.boardBody)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(Board.well, in: RoundedRectangle(cornerRadius: Board.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Board.Radius.control)
                    .strokeBorder(Board.outline, lineWidth: 1)
            }
    }
}

extension TextFieldStyle where Self == BoardFieldStyle {
    static var board: BoardFieldStyle { BoardFieldStyle() }
}

/// A setting that is on or off: title, optional explanation, native switch on the right.
struct SwitchRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        BoardRow {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.boardBody)
                        .foregroundStyle(Board.ink)
                    if let detail {
                        Text(detail)
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}
