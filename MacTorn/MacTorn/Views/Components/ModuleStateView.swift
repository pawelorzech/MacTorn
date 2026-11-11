import SwiftUI

/// What a module says about its own data when that is not simply "fresh": loading, stale,
/// offline, blocked by the key, rate limited, failed. Cached content stays on screen
/// underneath; this line adds the reason and one way out.
///
/// A fresh module with nothing to explain renders nothing — the header already shows when
/// the panel last updated, and a green "all good" above every screen is noise.
struct ModuleStateView: View {
    let state: ModulePresentationState
    let onRetry: () -> Void
    /// The concrete reason behind the state (e.g. "Your API key is paused"), shown
    /// under the status line so a module never needs a second, separate error row.
    var detail: String? = nil

    @Environment(\.openMacTornSettings) private var openSettings

    var body: some View {
        if state.kind != .fresh || detail != nil {
            BoardNotice(tone: tone, message: label, detail: detail, detailTestID: "uitest.error") {
                switch state.recovery {
                case .retry:
                    Button("Retry", action: onRetry)
                        .buttonStyle(.boardInline)
                        .uiTestID("uitest.moduleState.recovery")
                case .settings:
                    Button("Settings") { openSettings() }
                        .buttonStyle(.boardInline)
                        .uiTestID("uitest.moduleState.recovery")
                case .none:
                    EmptyView()
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    /// A message with a fresh module means another endpoint failed; the line is a warning
    /// then, so "Updated" does not contradict the reason underneath.
    private var tone: Board.Tone {
        if state.kind == .fresh { return .counting }
        switch state.kind {
        case .fresh, .loading, .empty: return .idle
        case .stale, .offline, .rateLimited: return .counting
        case .permission, .error: return .alert
        }
    }

    private var label: String {
        switch state.kind {
        case .loading:
            return "Loading data"
        case .empty:
            return state.updatedAt == nil ? "No data yet" : "No records"
        case .fresh:
            return state.updatedAt.map { "Updated \(relativeDate($0))" } ?? "Data available"
        case .stale:
            return state.updatedAt.map { "Stale, updated \(relativeDate($0))" } ?? "Data may be stale"
        case .offline:
            return state.hasContent ? "Offline, showing last data" : "No internet connection"
        case .permission:
            return state.hasContent ? "Permission changed, showing last data" : "API permission required"
        case .rateLimited:
            return state.hasContent ? "Rate limited, showing last data" : "Rate limited, retry shortly"
        case .error:
            return "Couldn’t refresh this module"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        TornFormatter.relativeDate(date, abbreviated: true)
    }
}
