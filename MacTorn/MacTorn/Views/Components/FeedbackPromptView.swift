import SwiftUI

struct FeedbackPromptView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: Board.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enjoying MacTorn?")
                    .font(.boardTitle)
                    .foregroundStyle(Board.ink)
                    .accessibilityAddTraits(.isHeader)

                Text("Your feedback helps make the app better for everyone.")
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                Button("Yes, leave a review") {
                    appState.feedbackResponded()
                    BrowserManager.shared.open(TornLink.page("forums.php#/p=threads&f=67&t=16532308"))
                }
                .buttonStyle(BoardButtonStyle(kind: .primary, fillsWidth: true))

                Button("Not really, send feedback") {
                    appState.feedbackResponded()
                    NSWorkspace.shared.open(URL(string: "mailto:pawel@orzech.me?subject=MacTorn%20Feedback")!)
                }
                .buttonStyle(.boardFill)
            }

            Button("Not now") {
                appState.feedbackDismissed()
            }
            .buttonStyle(.boardInline)
            .frame(maxWidth: .infinity)
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
}
