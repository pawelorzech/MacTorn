import SwiftUI
import AppKit

/// Local, read-only diagnostics. Shows environment, network/permission state,
/// the API budget and per-endpoint health, and copies a PII-safe report to the clipboard.
struct DiagnosticsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var report: DiagnosticsReport?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Board.Space.s) {
                Text("Diagnostics")
                    .font(.boardTitle)
                    .foregroundStyle(Board.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Board.Space.s)
                Button("Refresh") { Task { await load() } }
                    .buttonStyle(.board)
                    .accessibilityIdentifier("diagnostics.refresh")
                Button("Done") { dismiss() }
                    .buttonStyle(.board)
                    .accessibilityIdentifier("diagnostics.done")
            }
            .padding(.horizontal, Board.gutter)
            .padding(.top, Board.Space.m)
            .padding(.bottom, Board.Space.m)

            if let report {
                BoardPage {
                    BoardSection("Environment") {
                        ValueRow(label: "App", value: "\(report.appVersion) (\(report.build))", isFigure: false)
                        ValueRow(label: "macOS", value: report.osVersion, isFigure: false)
                        ValueRow(label: "Architecture", value: report.architecture, isFigure: false)
                    }

                    BoardSection("Runtime") {
                        ValueRow(label: "Network", value: report.isOnline ? "Online" : "Offline",
                                 tone: report.isOnline ? .ready : .alert, isFigure: false)
                        ValueRow(label: "Notifications", value: report.notificationPermission, isFigure: false)
                        ValueRow(label: "API key", value: report.keyPresent ? "Configured" : "Missing",
                                 tone: report.keyPresent ? nil : .alert, isFigure: false)
                        ValueRow(label: "Needs access", value: report.requiredAccessLevel, isFigure: false)
                        ValueRow(label: "Last refresh", value: lastRefreshText(report.lastSuccessfulRefresh), isFigure: false)
                        if let err = report.lastErrorSummary {
                            ValueRow(label: "Last error", value: err, tone: .alert, isFigure: false)
                        }
                    }

                    BoardSection("API budget") {
                        ValueRow(label: "Requests per minute", value: "\(report.requestsLastMinute)")
                        ValueRow(label: "Requests per day", value: "\(report.requestsLastDay)")
                        if report.recordsPerDayByCategory.isEmpty {
                            ValueRow(label: "Records per day", value: "None", isFigure: false)
                        } else {
                            ForEach(report.recordsPerDayByCategory.keys.sorted(), id: \.self) { key in
                                ValueRow(label: "Rows per day, \(key)", value: "\(report.recordsPerDayByCategory[key]!)")
                            }
                        }
                    }

                    if !report.suppressedEndpoints.isEmpty {
                        BoardSection("Not being requested") {
                            Text("MacTorn is skipping these on purpose.")
                                .font(.boardDetail)
                                .foregroundStyle(Board.inkSecondary)
                                .padding(.top, Board.Space.s)
                            ForEach(report.suppressedEndpoints.keys.sorted(), id: \.self) { key in
                                // The registry already carries a human name. Showing the slug
                                // beside a plain-words reason read as half translated, and
                                // VoiceOver spelled it out.
                                ValueRow(
                                    label: TornEndpointRegistry.endpoint(id: key)?.name ?? key,
                                    value: report.suppressionExplanations[key]
                                        ?? report.suppressedEndpoints[key]
                                        ?? "",
                                    isFigure: false
                                )
                            }
                        }
                    }

                    BoardSection("Endpoints") {
                        if report.endpoints.isEmpty {
                            BoardEmptyState(title: "No endpoints called yet")
                        } else {
                            ForEach(report.endpoints, id: \.endpointID) { e in
                                endpointRow(e)
                            }
                        }
                    }
                }

                Board.hairline.frame(height: 1)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.sanitizedText(), forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy sanitized report", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.boardFill)
                .padding(.horizontal, Board.gutter)
                .padding(.vertical, Board.Space.m)
                .accessibilityIdentifier("diagnostics.copy")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await load() }
            }
        }
        .frame(width: Board.panelWidth, height: 560)
        .background(Board.surface)
    }

    // MARK: - Data

    private func load() async {
        report = await appState.makeDiagnosticsReport()
        copied = false
    }

    // MARK: - Rows

    /// One endpoint: a state dot, its id, and how the last call went, in words as well as tone.
    private func endpointRow(_ e: EndpointHealth) -> some View {
        let tone = tone(for: e.outcome)
        return BoardRow {
            HStack(alignment: .firstTextBaseline, spacing: Board.Space.s) {
                StateDot(tone: tone)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                VStack(alignment: .leading, spacing: 1) {
                    Text(e.endpointID)
                        .font(.boardBody)
                        .foregroundStyle(Board.ink)
                    Text("\(label(for: e.outcome)), \(e.latencyMs) ms, \(byteText(e.responseBytes))")
                        .font(.boardDetail)
                        .foregroundStyle(tone.ink)
                }
                Spacer(minLength: Board.Space.s)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(e.endpointID): \(e.outcome.rawValue), \(e.latencyMs) milliseconds")
    }

    private func lastRefreshText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return TornFormatter.relativeDate(date)
    }

    private func byteText(_ bytes: Int) -> String {
        bytes <= 0 ? "no body" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }

    private func label(for outcome: EndpointOutcome) -> String {
        switch outcome {
        case .ok: return "OK"
        case .error: return "Error"
        case .offline: return "Offline"
        case .cancelled: return "Cancelled"
        case .pending: return "Pending"
        }
    }

    private func tone(for outcome: EndpointOutcome) -> Board.Tone {
        switch outcome {
        case .ok: return .ready
        case .error: return .alert
        case .offline, .pending: return .counting
        case .cancelled: return .idle
        }
    }
}
