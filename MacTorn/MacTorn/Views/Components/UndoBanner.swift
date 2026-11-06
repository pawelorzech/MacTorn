import SwiftUI

struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Button("Undo", action: onUndo)
                .buttonStyle(.borderless)
                .font(.caption.bold())
                .accessibilityLabel("Undo \(message)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.14))
        .cornerRadius(6)
    }
}
