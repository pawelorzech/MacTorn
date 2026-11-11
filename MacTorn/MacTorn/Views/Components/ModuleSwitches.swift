import SwiftUI

// The optional modules (API v2 extras) are switched on in Settings and then simply appear
// in the tab they belong to. Their switches, alert options and filters used to sit above
// the content of five tabs; configuration now lives in one place and the tabs show data.

extension CompanionStore.Feature {
    /// What turning this on adds, and where it shows up.
    var summary: String {
        switch self {
        case .recruiting: return "Open organized-crime slots at or above your pass rate. Shows in Faction."
        case .stocks: return "Bonus progress for your share blocks and bonuses ready to collect. Shows in Stocks."
        case .competition: return "Your side and score in the running competition, and Torn's calendar. Shows in Status."
        case .trades: return "Your open trades and what is being offered. Shows in Money."
        case .shops: return "What every shop sells and for how much. Shows in Travel."
        }
    }
}

/// When an optional module last heard from Torn, as a small button that asks again:
/// "checked 26 sec ago". Sits on the right of the module's section heading.
struct ModuleFreshness: View {
    @Environment(AppState.self) private var app
    let feature: CompanionStore.Feature

    private var canRefresh: Bool {
        !app.companion.isRefreshing && !app.keyHalted && app.connectivity.isConnected
    }

    var body: some View {
        if app.companion.isLoading(feature, app: app) {
            ProgressView().controlSize(.mini)
        } else {
            Button {
                app.companion.retry(feature, app: app)
            } label: {
                HStack(spacing: 4) {
                    if let checked = feature.endpointIDs.compactMap({ app.companion.fetchedAt[$0] }).min() {
                        Text("checked ") + Text(checked, style: .relative) + Text(" ago")
                    } else {
                        Text("not checked yet")
                    }
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh)
            .accessibilityLabel("Refresh \(feature.title)")
            .help("Refresh \(feature.title)")
        }
    }
}

/// Why an optional module has nothing new to show: offline, a paused key, or an endpoint
/// that answered with an error. Renders nothing when all is well.
struct ModuleIssues: View {
    @Environment(AppState.self) private var app
    @Environment(\.openMacTornSettings) private var openSettings
    let feature: CompanionStore.Feature

    var body: some View {
        let errors = feature.endpointIDs.compactMap { app.companion.errors[$0] }
        if !app.connectivity.isConnected {
            BoardNotice(tone: .counting, message: "No internet connection",
                        detail: "This module refreshes when you reconnect.")
                .padding(.top, Board.Space.s)
        } else if app.keyHalted {
            BoardNotice(tone: .alert, message: "This module needs a working API key") {
                Button("Settings") { openSettings() }.buttonStyle(.boardInline)
            }
            .padding(.top, Board.Space.s)
        } else {
            ForEach(Array(Set(errors)).sorted(), id: \.self) { error in
                BoardNotice(tone: .counting, message: error)
                    .padding(.top, Board.Space.s)
            }
        }
    }
}

/// Settings: one switch per optional module, with its alert option and filter underneath
/// once it is on.
struct ModuleSwitchList: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CompanionStore.Feature.allCases, id: \.self) { feature in
                SwitchRow(title: feature.title, detail: feature.summary, isOn: enabled(feature))

                if app.companion.enabled.contains(feature) {
                    if feature.canAlert {
                        SwitchRow(title: "Notify on changes", isOn: alerts(feature))
                            .padding(.leading, Board.Space.l)
                    }
                    if feature == .recruiting {
                        BoardRow {
                            Stepper(value: Binding(
                                get: { app.companion.minimumCPR },
                                set: { app.companion.minimumCPR = $0 }
                            ), in: 0...100, step: 5) {
                                Text("Minimum pass rate: \(app.companion.minimumCPR)%")
                                    .font(.boardBody)
                                    .foregroundStyle(Board.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .controlSize(.small)
                        }
                        .padding(.leading, Board.Space.l)
                    }
                }
            }
        }
    }

    private func enabled(_ feature: CompanionStore.Feature) -> Binding<Bool> {
        Binding(get: { app.companion.enabled.contains(feature) }, set: {
            app.companion.setEnabled(feature, $0, app: app)
            app.companion.start(app: app)
        })
    }

    private func alerts(_ feature: CompanionStore.Feature) -> Binding<Bool> {
        Binding(get: { app.companion.alerts.contains(feature) }, set: {
            app.companion.setAlerts(feature, $0)
        })
    }
}
