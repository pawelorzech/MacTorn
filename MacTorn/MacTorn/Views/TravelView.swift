import SwiftUI
import AppKit

// MARK: - Flying Status View (separate for proper live updates)
struct FlyingStatusView: View {
    @EnvironmentObject var appState: AppState
    let destination: String
    let timestamp: Int
    let departed: Int

    private var secondsRemaining: Int {
        appState.travelSecondsRemaining
    }

    private var progress: Double {
        let totalDuration = timestamp - departed
        guard totalDuration > 0 else { return 0 }
        return min(1.0, max(0.0, Double(totalDuration - secondsRemaining) / Double(totalDuration)))
    }

    private func formatTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "Arrived!" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airplane")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flying to \(destination)")
                        .font(.headline)
                    Text("In transit...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Arriving in:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(secondsRemaining))
                        .font(.title2.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

struct TravelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Travel Status Section
                travelStatusSection

                Divider()

                // Quick Travel Section (only when not traveling)
                if let travel = appState.data?.travel, !travel.isTraveling {
                    quickTravelSection(isAbroad: travel.isAbroad, currentLocation: travel.destination)
                    Divider()
                }

                // Pre-Arrival Alerts Section
                preArrivalAlertsSection

                // Quick Actions
                quickActionsSection
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Travel Status Section
    @ViewBuilder
    private var travelStatusSection: some View {
        if let travel = appState.data?.travel {
            if travel.isTraveling {
                // Flying state with live countdown - FlyingStatusView observes appState directly
                FlyingStatusView(
                    destination: travel.destination ?? "Unknown",
                    timestamp: travel.timestamp ?? 0,
                    departed: travel.departed ?? 0
                )
            } else if travel.isAbroad {
                // Abroad state
                abroadStatusView(travel)
            } else {
                // In Torn City
                inTornStatusView
            }
        } else {
            // No travel data
            inTornStatusView
        }
    }

    private func abroadStatusView(_ travel: Travel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("In \(travel.destination ?? "Unknown")")
                        .font(.headline)
                    Text("Currently abroad")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                if let url = URL(string: "https://www.torn.com/travelagency.php") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "airplane.departure")
                    Text("Return to Torn")
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var inTornStatusView: some View {
        HStack {
            Image(systemName: "house.fill")
                .font(.title2)
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("In Torn City")
                    .font(.headline)
                Text("Ready to travel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Quick Travel Section
    private func quickTravelSection(isAbroad: Bool, currentLocation: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(.secondary)
                Text("Quick Travel")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
            }

            if isAbroad {
                // Show only return button when abroad
                Button {
                    if let url = URL(string: "https://www.torn.com/travelagency.php") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text("Torn")
                        Text("Return Home")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                // Show all destinations grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(TornDestination.allCases) { destination in
                        destinationButton(destination)
                    }
                }
            }
        }
    }

    private func destinationButton(_ destination: TornDestination) -> some View {
        Button {
            NSWorkspace.shared.open(destination.travelAgencyURL)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(destination.flag)
                        .font(.title3)
                    Text(destination.rawValue)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text("~\(destination.flightTimeFormatted)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pre-Arrival Alerts Section
    private var preArrivalAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundColor(.secondary)
                Text("Pre-Arrival Alerts")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(appState.travelNotificationSettings) { setting in
                    Toggle(isOn: Binding(
                        get: { setting.enabled },
                        set: { newValue in
                            var updated = setting
                            updated.enabled = newValue
                            appState.updateTravelNotificationSetting(updated)
                        }
                    )) {
                        Text(setting.displayName)
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
                Text("Quick Actions")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://www.torn.com/travelagency.php") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "airplane.departure")
                        Text("Travel Agency")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://www.torn.com/page.php?sid=ItemMarket") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "storefront")
                        Text("Abroad")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers
    private func formatTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "Arrived!" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
