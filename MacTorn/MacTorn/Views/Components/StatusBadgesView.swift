import SwiftUI

struct StatusBadgesView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let status: Status
    /// Mac↔Torn skew (issue #46). `status.until` is an absolute server timestamp, so the
    /// badge counts down against Torn's now, matching the menu bar and the timeline.
    var serverClock: ServerClock = .synchronized

    private var remaining: Int { status.timeRemaining(at: serverClock.serverNow(Date())) }

    var body: some View {
        if !status.isOkay {
            HStack(spacing: 8) {
                if status.isInHospital {
                    HStack(spacing: 4) {
                        Image(systemName: "cross.circle.fill")
                            .foregroundColor(.red)
                            .accessibilityHidden(true)
                        Text("Hospital")
                            .font(.caption.bold())
                        Text(TornFormatter.clock(remaining, zeroText: "0:00"))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(reduceTransparency ? 0.4 : 0.1))
                    .cornerRadius(6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("In hospital, \(TornFormatter.clock(remaining, zeroText: "0:00")) remaining")
                    .uiTestID("uitest.status.hospital")
                }

                if status.isInJail {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                        Text("Jail")
                            .font(.caption.bold())
                        Text(TornFormatter.clock(remaining, zeroText: "0:00"))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(reduceTransparency ? 0.4 : 0.1))
                    .cornerRadius(6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("In jail, \(TornFormatter.clock(remaining, zeroText: "0:00")) remaining")
                    .uiTestID("uitest.status.jail")
                }
            }
        }
    }
}
