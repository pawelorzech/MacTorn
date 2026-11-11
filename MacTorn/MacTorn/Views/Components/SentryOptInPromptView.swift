import SwiftUI

/// One-time prompt asking the user to opt into anonymous crash reporting.
/// Shown after upgrading to a version that ships Sentry. Default stays OFF
/// regardless; the prompt just makes the toggle discoverable.
struct SentryOptInPromptView: View {
    @AppStorage(SentryManager.enabledKey) private var sentryEnabled: Bool = false
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Board.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Help fix MacTorn bugs")
                    .font(.boardTitle)
                    .foregroundStyle(Board.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("Send anonymous crash reports? Off by default, and you can change it any time in Settings.")
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Never sent: API key, player name, in-game data.")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button("Keep off") {
                    sentryEnabled = false
                    SentryManager.applyState()
                    dismiss()
                }
                .buttonStyle(.boardFill)

                Button("Enable") {
                    sentryEnabled = true
                    SentryManager.applyState()
                    dismiss()
                }
                .buttonStyle(BoardButtonStyle(kind: .primary, fillsWidth: true))
            }
        }
        .padding(Board.gutter)
        .frame(width: 280)
        // The one boxed surface in the app: a modal card over a dimmed panel. Opaque, no
        // shadow, so it reads the same under Reduce Transparency.
        .background(Board.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(Board.outline, lineWidth: 1)
        }
    }

    private func dismiss() {
        SentryManager.markPromptShown()
        isPresented = false
    }
}
