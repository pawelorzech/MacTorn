import SwiftUI

/// "Nothing here yet" placeholder: icon + title + optional subtitle, centred.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// Icon-over-title button on a tinted rounded background — the shared shape behind the
/// per-tab "quick action" tiles.
struct TileButton: View {
    let title: String
    let icon: String
    let color: Color
    var iconFont: Font = .body
    var titleFont: Font = .caption2
    var spacing: CGFloat = 4
    var verticalPadding: CGFloat = 8
    var cornerRadius: CGFloat = 8
    var opacity: Double = 0.1
    let action: () -> Void

    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            VStack(spacing: spacing) {
                Image(systemName: icon)
                    .font(iconFont)
                    .accessibilityHidden(true)
                Text(title)
                    .font(titleFont)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(color.opacity(reduceTransparency ? 0.4 : opacity))
            .foregroundColor(color)
            .cornerRadius(cornerRadius)
        }
        .buttonStyle(.plain)
    }
}