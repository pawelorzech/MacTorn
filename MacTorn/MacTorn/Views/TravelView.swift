import SwiftUI

/// Where the player is, how long until they land, and what the trip is worth: flight
/// times, landing alerts and shop prices.
struct TravelView: View {
    @Environment(AppState.self) private var appState
    // Deliberately separate from the legacy `privateIsland` preference: owning or
    // renting a PI does not prove that its Airstrip upgrade exists or that a pilot
    // is currently hired.
    @AppStorage("travelFlightMethod")
    private var flightMethodRawValue = TornDestination.FlightMethod.standard.rawValue

    private var selectedFlightMethod: TornDestination.FlightMethod {
        TornDestination.FlightMethod(rawValue: flightMethodRawValue) ?? .standard
    }

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(for: .travel, hasContent: appState.player.data?.travel != nil),
                onRetry: appState.refreshNow
            )

            if let travel = appState.player.data?.travel {
                if travel.isTraveling {
                    FlightBoard(travel: travel)
                } else if travel.isAbroad {
                    abroad(travel)
                } else {
                    PlaceLine(tone: .ready, place: "In Torn", note: "Ready to travel")
                }
            } else {
                // No travel data: don't claim "In Torn" — the player may well be abroad.
                BoardEmptyState(title: "Travel status unavailable",
                                detail: "Torn hasn't told MacTorn where you are yet.")
            }

            alertsSection

            if let travel = appState.player.data?.travel, !travel.isTraveling, !travel.isAbroad {
                flightTimesSection
            }

            ShopPricesPanel()

            BoardSection("Open in Torn") {
                TornLinks(links: [
                    TornLinks.Link(title: "Travel agency", url: TornLink.travelAgency),
                    TornLinks.Link(title: "Item market", url: TornLink.itemMarket),
                ], columns: 2)
                .padding(.top, Board.Space.s)
            }
        }
    }

    // MARK: - Abroad

    private func abroad(_ travel: Travel) -> some View {
        VStack(alignment: .leading, spacing: Board.Space.m) {
            PlaceLine(tone: .idle,
                      place: travel.destination.map { "In \($0)" } ?? "Abroad",
                      note: "Away from Torn")
            Button("Return to Torn") { openTorn(TornLink.travelAgency) }
                .buttonStyle(.boardPrimary)
                .accessibilityHint("Opens the travel agency in your browser")
        }
    }

    // MARK: - Landing alerts

    private var alertsSection: some View {
        BoardSection("Alert me before landing") {
            HStack(spacing: 6) {
                ForEach(appState.travelNotificationSettings) { setting in
                    ToggleChip(title: Self.shortName(setting), isOn: Binding(
                        get: { setting.enabled },
                        set: { newValue in
                            var updated = setting
                            updated.enabled = newValue
                            appState.updateTravelNotificationSetting(updated)
                        }
                    ))
                    .accessibilityLabel(setting.displayName)
                }
            }
            .padding(.top, Board.Space.s)
        }
    }

    /// "2 min", "30 sec": the section heading already says "before landing".
    private static func shortName(_ setting: TravelNotificationSetting) -> String {
        setting.displayName.replacingOccurrences(of: " before", with: "")
    }

    // MARK: - Flight times

    private var flightTimesSection: some View {
        BoardSection(title: "Flight times", trailing: {
            Picker("Estimate method", selection: $flightMethodRawValue) {
                ForEach(TornDestination.FlightMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method.rawValue)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Flight time estimate method")
            .help("Airstrip estimates require both the Airstrip upgrade and a hired pilot.")
        }) {
            ForEach(TornDestination.allCases) { destination in
                Button {
                    BrowserManager.shared.open(TornLink.travelAgency)
                } label: {
                    BoardRow(verticalPadding: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: Board.Space.s) {
                            Text(destination.flag)
                                .font(.boardBody)
                                .accessibilityHidden(true)
                            Text(destination.rawValue)
                                .font(.boardBody)
                                .foregroundStyle(Board.ink)
                            Spacer(minLength: Board.Space.s)
                            Text(destination.flightTimeFormatted(method: selectedFlightMethod))
                                .font(.figureValue)
                                .foregroundStyle(Board.ink)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(destination.rawValue), about \(destination.flightTimeFormatted(method: selectedFlightMethod))")
                .accessibilityHint("Estimated with \(selectedFlightMethod.rawValue.lowercased()) travel. Opens the travel agency.")
            }

            Text(estimateNote)
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Board.Space.s)
        }
    }

    private var estimateNote: String {
        let base = "Torn's base times; a real flight can differ by ±\(TornDestination.estimateVariancePercent)%. "
            + "A flight in progress counts down from Torn's own arrival time."
        return selectedFlightMethod == .airstrip
            ? "Airstrip times need the Private Island Airstrip upgrade and a hired pilot. " + base
            : base
    }
}

/// "In Torn" / "In Japan": the place as the screen's headline, with a state dot.
private struct PlaceLine: View {
    let tone: Board.Tone
    let place: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(place)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Board.ink)
            HStack(spacing: 6) {
                StateDot(tone: tone)
                Text(note)
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A flight in progress: the one screen where a single countdown gets the whole width.
/// Observes `travelSecondsRemaining`, which AppState ticks against Torn's clock.
struct FlightBoard: View {
    @Environment(AppState.self) private var appState
    /// `destination` is optional because `Travel.isTraveling` only requires a positive
    /// `time_left`: Torn can report an in-progress flight before the destination is set.
    let travel: Travel

    private var secondsRemaining: Int { appState.player.travelSecondsRemaining }

    private var progress: Double {
        Travel.flightProgress(arrival: travel.timestamp ?? 0, departure: travel.departed ?? 0,
                              remainingSeconds: secondsRemaining)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: Board.Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flying to")
                        .font(.boardCaption)
                        .foregroundStyle(Board.inkSecondary)
                    Text(travel.destination ?? "Destination pending")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: Board.Space.s)
                Text(TornFormatter.clock(secondsRemaining, zeroText: "Landed"))
                    .font(.figureHero)
                    .foregroundStyle(Board.Tone.counting.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            ProgressLine(progress: progress, color: Board.Tone.counting.fill, height: 4)
                .accessibilityHidden(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Flight progress")
                .accessibilityValue("\(Int(progress * 100)) percent")
                .uiTestID("uitest.travel.progress")

            HStack(alignment: .firstTextBaseline) {
                if let departed = travel.departed, departed > 0 {
                    Text("Left \(Self.time(departed))")
                }
                Spacer(minLength: Board.Space.s)
                if let arrival = travel.timestamp, arrival > 0 {
                    Text("Lands \(Self.time(arrival))")
                }
            }
            .font(.boardCaption)
            .foregroundStyle(Board.inkSecondary)
        }
        .transaction { $0.animation = nil }
    }

    private static func time(_ unix: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(unix)).formatted(date: .omitted, time: .shortened)
    }
}
