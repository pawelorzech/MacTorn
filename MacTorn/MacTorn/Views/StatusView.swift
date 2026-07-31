import SwiftUI

struct StatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    @AppStorage("boosterCooldownTarget") private var boosterCooldownTarget: String = "boosters"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                headerSection

                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["user.fast", "user.v2", "user.activity"],
                        hasContent: appState.data != nil,
                        staleAfter: 120
                    ),
                    onRetry: appState.refreshNow
                )

                // Next Action timeline (Etap J) — the single most useful glance.
                if appState.data != nil {
                    NextActionView(reduceTransparency: reduceTransparency)
                }

                // Error state
                if let error = appState.errorMsg {
                    errorSection(error)
                }
                
                // Status badges (Hospital/Jail)
                if let status = appState.data?.status {
                    StatusBadgesView(status: status)
                }
                
                // Chain status
                if let chain = appState.data?.chain, let fetchTime = appState.lastUpdated {
                    ChainView(chain: chain, fetchTime: fetchTime)
                }
                
                // Travel status
                if let travel = appState.data?.travel, travel.isTraveling || travel.isAbroad {
                    travelSection(travel)
                }
                
                // Bars
                if let bars = appState.data?.bars {
                    barsSection(bars)
                }
                
                // Cooldowns
                if let cooldowns = appState.data?.cooldowns {
                    cooldownsSection(cooldowns)
                }

                // Bounty alert — someone placed a bounty on you (safety signal)
                if !appState.bountiesOnMe.isEmpty {
                    bountyBadge
                }

                // Dailies (refills + education) — from the v2 user call
                dailiesSection

                // Messages badge
                if appState.unreadMessages > 0 {
                    messagesBadge
                }

                // Events
                if !appState.activityEvents.isEmpty {
                    EventsView(events: appState.activityEvents)
                }
                
                // Quick Links
                quickLinksSection
            }
            .padding(12)
        }
        .frame(maxHeight: 480)
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let name = appState.data?.name, let id = appState.data?.playerId {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                        Text("[\(String(id))]")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Torn Status")
                        .font(.headline)
                }
                
                Spacer()
                
                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Button {
                        appState.refreshNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Refresh Torn data")
                }
            }
        }
    }
    
    // MARK: - Messages Badge
    private var messagesBadge: some View {
        Button {
            if let url = URL(string: "https://www.torn.com/messages.php") {
                BrowserManager.shared.open(url)
            }
        } label: {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)
                Text("\(appState.unreadMessages) unread messages")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(reduceTransparency ? 0.2 : 0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Error
    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .uiTestID("uitest.error")
    }
    
    // MARK: - Travel
    private func travelSection(_ travel: Travel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "airplane")
                    .foregroundColor(.blue)
                Text(travel.isTraveling ? "Traveling to \(travel.destination ?? "Unknown")" : "In \(travel.destination ?? "Unknown")")
                    .font(.caption.bold())
            }

            if travel.isTraveling {
                HStack {
                    Text("Arriving in:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatTime(appState.travelSecondsRemaining))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(reduceTransparency ? 0.2 : 0.1))
        .cornerRadius(8)
        .transaction { $0.animation = nil }
    }
    
    // MARK: - Bars
    private func barsSection(_ bars: Bars) -> some View {
        VStack(spacing: 10) {
            ProgressBarView(
                label: "Energy",
                current: bars.energy.current,
                maximum: bars.energy.maximum,
                color: .green,
                icon: "bolt.fill"
            )
            
            ProgressBarView(
                label: "Nerve",
                current: bars.nerve.current,
                maximum: bars.nerve.maximum,
                color: .red,
                icon: "flame.fill"
            )
            
            ProgressBarView(
                label: "Happy",
                current: bars.happy.current,
                maximum: bars.happy.maximum,
                color: .yellow,
                icon: "face.smiling.fill"
            )
            
            ProgressBarView(
                label: "Life",
                current: bars.life.current,
                maximum: bars.life.maximum,
                color: .blue,
                icon: "heart.fill"
            )
        }
    }
    
    // MARK: - Cooldowns
    private func cooldownsSection(_ cooldowns: Cooldowns) -> some View {
        let drugURL = URL(string: "https://www.torn.com/item.php#drugs-items")
        let medicalURL = URL(string: "https://www.torn.com/item.php#medical-items")
        let boosterURL = boosterCooldownTarget == "alcohol"
            ? URL(string: "https://www.torn.com/item.php#alcohol-items")
            : URL(string: "https://www.torn.com/item.php#boosters-items")
        let boosterLabel = boosterCooldownTarget == "alcohol" ? "Use Alcohol →" : "Use Booster →"

        return VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Cooldowns")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                if let ends = appState.cooldownEnds {
                    LiveCooldownItem(label: "Drug", endsAt: ends.drugEndsAt, icon: "pills.fill", actionURL: drugURL, actionLabel: "Use Drug →")
                    LiveCooldownItem(label: "Medical", endsAt: ends.medicalEndsAt, icon: "cross.case.fill", actionURL: medicalURL, actionLabel: "Use Medical →")
                    LiveCooldownItem(label: "Booster", endsAt: ends.boosterEndsAt, icon: "arrow.up.circle.fill", actionURL: boosterURL, actionLabel: boosterLabel)
                } else {
                    CooldownItem(label: "Drug", seconds: cooldowns.drug, icon: "pills.fill", actionURL: drugURL, actionLabel: "Use Drug →")
                    CooldownItem(label: "Medical", seconds: cooldowns.medical, icon: "cross.case.fill", actionURL: medicalURL, actionLabel: "Use Medical →")
                    CooldownItem(label: "Booster", seconds: cooldowns.booster, icon: "arrow.up.circle.fill", actionURL: boosterURL, actionLabel: boosterLabel)
                }
            }
        }
    }
    
    // MARK: - Quick Links
    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Quick Links")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(appState.shortcutsManager.shortcuts) { shortcut in
                    Button {
                        appState.shortcutsManager.openURL(shortcut.url)
                    } label: {
                        Text(shortcut.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.accentColor.opacity(reduceTransparency ? 0.2 : 0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                // TRI Hub link
                Button {
                    if let url = URL(string: "https://hub.tri.ovh") {
                        BrowserManager.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text("TRI Hub")
                            .font(.caption2)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Color.purple.opacity(reduceTransparency ? 0.3 : 0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Bounty Alert
    private var bountyBadge: some View {
        let total = appState.bountiesOnMe.reduce(0) { $0 + $1.reward }
        let count = appState.bountiesOnMe.count
        let amount = AppState.decimalFormatter.string(from: NSNumber(value: total)) ?? "\(total)"
        return Button {
            BrowserManager.shared.open(URL(string: "https://www.torn.com/bounties.php")!)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .foregroundColor(.red)
                Text(count == 1 ? "Bounty on you" : "\(count) bounties on you")
                    .font(.caption.bold())
                Spacer()
                Text("$\(amount)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.red.opacity(reduceTransparency ? 0.3 : 0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dailies (refills + education)
    @ViewBuilder
    private var dailiesSection: some View {
        let refills = appState.refills
        let studying = appState.education?.isStudying ?? false
        if refills != nil || studying {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(.mint)
                    Text("Dailies")
                        .font(.caption.bold())
                }

                if let refills {
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .foregroundColor(.cyan)
                            .font(.caption2)
                        if refills.unclaimed.isEmpty {
                            Text("Refills claimed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Refills left: \(refills.unclaimed.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                // `endsDate` is an absolute time, so tick `now` against it — no drift.
                if let ends = appState.education?.endsDate {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        let remaining = max(0, Int(ends.timeIntervalSince(context.date)))
                        HStack(spacing: 6) {
                            Image(systemName: "graduationcap.fill")
                                .foregroundColor(.purple)
                                .font(.caption2)
                            Text(remaining > 0
                                 ? "Education: \(formatDuration(remaining)) left"
                                 : "Education: complete")
                                .font(.caption)
                                .foregroundColor(remaining > 0 ? .secondary : .green)
                        }
                    }
                }
            }
            .padding()
            .background(Color.mint.opacity(reduceTransparency ? 0.25 : 0.06))
            .cornerRadius(8)
        }
    }

    // MARK: - Helpers
    private func formatTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Day-aware duration for long timers like education (can span days).
    private func formatDuration(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

// MARK: - Cooldown Item
struct CooldownItem: View {
    let label: String
    let seconds: Int
    let icon: String
    var actionURL: URL? = nil
    var actionLabel: String? = nil

    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        if seconds <= 0, let url = actionURL {
            Button {
                BrowserManager.shared.open(url)
            } label: {
                cellContent(remaining: seconds)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(label)")
            .accessibilityHint("Opens Torn items page in browser")
        } else {
            cellContent(remaining: seconds)
        }
    }

    private func cellContent(remaining: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(remaining > 0 ? .orange : .green)

            Text(formattedTime)
                .font(.caption2.monospacedDigit())
                .foregroundColor(remaining > 0 ? .primary : .green)
                .fontWeight(remaining <= 0 ? .bold : .regular)

            if remaining <= 0, let actionLabel {
                Text(actionLabel)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, remaining <= 0 && actionURL != nil ? 4 : 0)
        .background(
            remaining <= 0 && actionURL != nil
                ? Color.green.opacity(reduceTransparency ? 0.25 : 0.12)
                : Color.clear
        )
        .overlay {
            if remaining <= 0 && actionURL != nil {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.green.opacity(reduceTransparency ? 0.4 : 0.25))
            }
        }
        .cornerRadius(6)
    }

    private var formattedTime: String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Live Cooldown Item
//
// Receives the *absolute* end-timestamp (Unix seconds) the cooldown will expire
// at, computed once at fetch time from the server's response timestamp. Each
// tick recomputes `endsAt - now` — never `originalSeconds - elapsed` — so the
// countdown stays drift-free against torn.com.
//
// `endsAt == 0` means the cooldown is not active.
struct LiveCooldownItem: View {
    let label: String
    let endsAt: Int
    let icon: String
    var actionURL: URL? = nil
    var actionLabel: String? = nil

    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let remaining = endsAt > 0
                ? max(0, endsAt - Int(context.date.timeIntervalSince1970))
                : 0

            if remaining <= 0, let url = actionURL {
                Button {
                    BrowserManager.shared.open(url)
                } label: {
                    cellContent(remaining: remaining)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(label)")
                .accessibilityHint("Opens Torn items page in browser")
            } else {
                cellContent(remaining: remaining)
            }
        }
    }

    private func cellContent(remaining: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(remaining > 0 ? .orange : .green)

            Text(formattedTime(remaining))
                .font(.caption2.monospacedDigit())
                .foregroundColor(remaining > 0 ? .primary : .green)
                .fontWeight(remaining <= 0 ? .bold : .regular)

            if remaining <= 0, let actionLabel {
                Text(actionLabel)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, remaining <= 0 && actionURL != nil ? 4 : 0)
        .background(
            remaining <= 0 && actionURL != nil
                ? Color.green.opacity(reduceTransparency ? 0.25 : 0.12)
                : Color.clear
        )
        .overlay {
            if remaining <= 0 && actionURL != nil {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.green.opacity(reduceTransparency ? 0.4 : 0.25))
            }
        }
        .cornerRadius(6)
    }

    private func formattedTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
