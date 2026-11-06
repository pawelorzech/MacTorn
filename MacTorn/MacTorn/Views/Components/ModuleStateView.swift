import SwiftUI

/// Shared, compact status for feature modules. Successful cached content stays visible
/// during transient failures; this view only adds freshness and a recovery action.
struct ModuleStateView: View {
    let state: ModulePresentationState
    let onRetry: () -> Void
    /// The concrete reason behind the state (e.g. "Your API key is paused"), shown
    /// under the status line so a module never needs a second, separate error row.
    var detail: String? = nil

    @Environment(\.openMacTornSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusRow
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .uiTestID("uitest.error")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(barColor.opacity(state.kind == .fresh && detail == nil ? 0.06 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }

    /// A message with a fresh module means another endpoint failed; tint the bar so the
    /// green "Updated" does not contradict the reason underneath.
    private var barColor: Color {
        state.kind == .fresh && detail != nil ? .orange : color
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                if state.kind == .loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                }

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(state.kind == .fresh ? Color.secondary : color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)

            Spacer(minLength: 4)

            switch state.recovery {
            case .retry:
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .uiTestID("uitest.moduleState.recovery")
            case .settings:
                Button("Settings") { openSettings() }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .uiTestID("uitest.moduleState.recovery")
            case .none:
                EmptyView()
            }
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
            return state.updatedAt.map { "Stale · updated \(relativeDate($0))" } ?? "Data may be stale"
        case .offline:
            return state.hasContent ? "Offline · showing last data" : "No internet connection"
        case .permission:
            return state.hasContent ? "Permission changed · showing last data" : "API permission required"
        case .rateLimited:
            return state.hasContent ? "Rate limited · showing last data" : "Rate limited · retry shortly"
        case .error:
            return "Couldn’t refresh this module"
        }
    }

    private var icon: String {
        switch state.kind {
        case .loading: return "clock"
        case .empty: return "tray"
        case .fresh: return "checkmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .offline: return "wifi.slash"
        case .permission: return "lock.trianglebadge.exclamationmark"
        case .rateLimited: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state.kind {
        case .fresh: return .green
        case .loading, .empty: return .secondary
        case .stale, .offline, .rateLimited: return .orange
        case .permission, .error: return .red
        }
    }

    private func relativeDate(_ date: Date) -> String {
        TornFormatter.relativeDate(date, abbreviated: true)
    }
}
