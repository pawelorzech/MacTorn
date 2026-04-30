import SwiftUI

/// One-time prompt asking the user to opt into anonymous crash reporting.
/// Shown after upgrading to a version that ships Sentry. Default stays OFF
/// regardless — the prompt just makes the toggle discoverable.
struct SentryOptInPromptView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    @AppStorage(SentryManager.enabledKey) private var sentryEnabled: Bool = false
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 32))
                .foregroundColor(.purple)

            Text("Help fix MacTorn bugs")
                .font(.headline)

            Text("Send anonymous crash reports? OFF by default — you can toggle it any time in Settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Never sent: API key, player name, in-game data.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    sentryEnabled = false
                    SentryManager.applyState()
                    dismiss()
                } label: {
                    Text("Keep off")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(reduceTransparency ? 0.3 : 0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    sentryEnabled = true
                    SentryManager.applyState()
                    dismiss()
                } label: {
                    Text("Enable")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(reduceTransparency ? 0.5 : 0.85))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }

    private func dismiss() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        UserDefaults.standard.set(version, forKey: SentryManager.promptShownKey)
        isPresented = false
    }
}
