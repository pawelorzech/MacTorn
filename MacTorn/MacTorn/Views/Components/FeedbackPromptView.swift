import SwiftUI

struct FeedbackPromptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.pink, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Enjoying MacTorn?")
                .font(.headline)

            Text("Your feedback helps make the app better for everyone.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    appState.feedbackRespondedPositive()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.thumbsup.fill")
                        Text("Yes! Leave a review")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(reduceTransparency ? 0.4 : 0.2))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    appState.feedbackRespondedNegative()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope.fill")
                        Text("Not really — send feedback")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(reduceTransparency ? 0.4 : 0.2))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Button {
                appState.feedbackDismissed()
            } label: {
                Text("Not now")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(reduceTransparency ? Color(.windowBackgroundColor) : Color(.windowBackgroundColor).opacity(0.95))
                .shadow(radius: 8)
        )
    }
}
