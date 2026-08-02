import SwiftUI
import AppKit

// MARK: - Flying Status View (separate for proper live updates)
struct FlyingStatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
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
                            .fill(Color.gray.opacity(reduceTransparency ? 0.5 : 0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progress, height: 8)
                    }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Flight progress")
                .accessibilityValue("\(Int(progress * 100)) percent")
                .uiTestID("uitest.travel.progress")
            }
        }
        .padding()
        .background(Color.blue.opacity(reduceTransparency ? 0.2 : 0.1))
        .cornerRadius(12)
        .transaction { $0.animation = nil }
    }
}

struct TravelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    // Deliberately separate from the legacy `privateIsland` preference: owning or
    // renting a PI does not prove that its Airstrip upgrade exists or that a pilot
    // is currently hired.
    @AppStorage("travelFlightMethod")
    private var flightMethodRawValue = TornDestination.FlightMethod.standard.rawValue

    private var selectedFlightMethod: TornDestination.FlightMethod {
        TornDestination.FlightMethod(rawValue: flightMethodRawValue) ?? .standard
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["user.fast"],
                        hasContent: appState.data?.travel != nil,
                        staleAfter: 120
                    ),
                    onRetry: appState.refreshNow
                )

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
                    BrowserManager.shared.open(url)
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
        .background(Color.orange.opacity(reduceTransparency ? 0.2 : 0.1))
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
        .background(Color.green.opacity(reduceTransparency ? 0.2 : 0.1))
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
                Spacer()
                if !isAbroad {
                    Picker("Estimate method", selection: $flightMethodRawValue) {
                        ForEach(TornDestination.FlightMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method.rawValue)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("Quick Travel estimate method")
                    .help("Airstrip estimates require both the Airstrip upgrade and a hired pilot.")
                }
            }

            if isAbroad {
                // Show only return button when abroad
                Button {
                    if let url = URL(string: "https://www.torn.com/travelagency.php") {
                        BrowserManager.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text("Torn")
                        Text("Return Home")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(reduceTransparency ? 0.2 : 0.1))
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

                if selectedFlightMethod == .airstrip {
                    Text("Requires a Private Island Airstrip upgrade and a currently hired pilot.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    "Current Torn base estimates; actual flights can vary by "
                        + "±\(TornDestination.estimateVariancePercent)%. "
                        + "Active-flight countdowns use API arrival data."
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func destinationButton(_ destination: TornDestination) -> some View {
        Button {
            BrowserManager.shared.open(destination.travelAgencyURL)
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(destination.flag)
                        .font(.title3)
                    Text(destination.rawValue)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text(
                    "~\(destination.flightTimeFormatted(method: selectedFlightMethod))"
                )
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(reduceTransparency ? 0.2 : 0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            "Estimated with \(selectedFlightMethod.rawValue.lowercased()) travel"
        )
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
            .background(Color.secondary.opacity(reduceTransparency ? 0.2 : 0.1))
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
                        BrowserManager.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "airplane.departure")
                        Text("Travel Agency")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(reduceTransparency ? 0.2 : 0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    if let url = URL(string: "https://www.torn.com/page.php?sid=ItemMarket") {
                        BrowserManager.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "storefront")
                        Text("Abroad")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(reduceTransparency ? 0.2 : 0.1))
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
