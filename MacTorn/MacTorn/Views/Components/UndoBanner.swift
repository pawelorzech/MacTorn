import SwiftUI

/// A removal that can still be taken back: one line in the notice style with an inline
/// "Undo".
struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        BoardNotice(tone: .idle, message: message) {
            Button("Undo", action: onUndo)
                .buttonStyle(.boardInline)
                .frame(minWidth: 44, minHeight: 28)
                .contentShape(Rectangle())
                .accessibilityLabel("Undo \(message)")
        }
    }
}
