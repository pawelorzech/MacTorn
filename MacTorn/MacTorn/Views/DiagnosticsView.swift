import SwiftUI
import AppKit

/// Local, read-only diagnostics (Etap F). Shows environment, network/permission state,
/// the API budget and per-endpoint health, and copies a PII-safe report to the clipboard.
struct DiagnosticsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var report: DiagnosticsReport?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Refresh") { Task { await load() } }
                    .accessibilityIdentifier("diagnostics.refresh")
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("diagnostics.done")
            }

            if let report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        section("Environment") {
                            row("App", "\(report.appVersion) (\(report.build))")
                            row("macOS", report.osVersion)
                            row("Architecture", report.architecture)
                        }
                        section("Runtime") {
                            row("Network", report.isOnline ? "online" : "offline")
                            row("Notifications", report.notificationPermission)
                            row("API key", report.keyPresent ? "configured" : "missing")
                            row("Needs access", report.requiredAccessLevel)
                            row("Last refresh", lastRefreshText(report.lastSuccessfulRefresh))
                            if let err = report.lastErrorSummary {
                                row("Last error", err)
                            }
                        }
                        section("API budget") {
                            row("Requests / min", "\(report.requestsLastMinute)")
                            row("Requests / day", "\(report.requestsLastDay)")
                            if report.recordsPerDayByCategory.isEmpty {
                                row("Records / day", "none")
                            } else {
                                ForEach(report.recordsPerDayByCategory.keys.sorted(), id: \.self) { key in
                                    row("Rows/day · \(key)", "\(report.recordsPerDayByCategory[key]!)")
                                }
                            }
                        }
                        section("Endpoints") {
                            if report.endpoints.isEmpty {
                                Text("No endpoints called yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(report.endpoints, id: \.endpointID) { e in
                                    HStack {
                                        Image(systemName: icon(for: e.outcome))
                                            .foregroundStyle(color(for: e.outcome))
                                            .accessibilityHidden(true)
                                        Text(e.endpointID).font(.caption)
                                        Spacer()
                                        Text("\(e.latencyMs)ms · \(byteText(e.responseBytes))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("\(e.endpointID): \(e.outcome.rawValue), \(e.latencyMs) milliseconds")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.sanitizedText(), forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied ✓" : "Copy sanitized report", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("diagnostics.copy")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await load() }
            }
        }
        .padding()
        .frame(width: 380, height: 500)
    }

    // MARK: - Data

    private func load() async {
        report = await appState.makeDiagnosticsReport()
        copied = false
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func lastRefreshText(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func byteText(_ bytes: Int) -> String {
        bytes <= 0 ? "—" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func icon(for outcome: EndpointOutcome) -> String {
        switch outcome {
        case .ok: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .offline: return "wifi.slash"
        case .cancelled: return "slash.circle"
        case .pending: return "clock"
        }
    }

    private func color(for outcome: EndpointOutcome) -> Color {
        switch outcome {
        case .ok: return .green
        case .error: return .red
        case .offline, .cancelled, .pending: return .orange
        }
    }
}
