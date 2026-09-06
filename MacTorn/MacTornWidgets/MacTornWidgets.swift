import SwiftUI
import WidgetKit

struct TornEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}
struct TornProvider: TimelineProvider {
    func placeholder(in context: Context) -> TornEntry { .init(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (TornEntry) -> Void) {
        completion(.init(date: Date(), snapshot: context.isPreview ? .preview : WidgetSnapshotStore.shared.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TornEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.shared.read()
        // Scheduled entries update readiness and stale state without new API requests.
        var dates = [now, now.addingTimeInterval(301)]
        if let snapshot {
            if let arrival = snapshot.arrival, arrival > now { dates.append(arrival) }
            dates += snapshot.events.map(\.date).filter { $0 > now && $0 < now.addingTimeInterval(3600) }
            dates.append(max(now.addingTimeInterval(1), snapshot.updatedAt.addingTimeInterval(301)))
        }
        completion(Timeline(entries: Array(Set(dates)).sorted().map { .init(date: $0, snapshot: snapshot) },
                            policy: .after(now.addingTimeInterval(900))))
    }
}

enum TornWidgetKind: String {
    case status, next, travel
    var title: String {
        switch self { case .status: "Player Status"; case .next: "What's Next?"; case .travel: "Travel" }
    }
    var symbol: String {
        switch self { case .status: "chart.bar.fill"; case .next: "clock.fill"; case .travel: "airplane" }
    }
}
struct TornWidgetView: View {
    let entry: TornEntry
    let kind: TornWidgetKind
    @Environment(\.widgetFamily) private var systemFamily
    var previewFamily: WidgetFamily? = nil
    private var family: WidgetFamily { previewFamily ?? systemFamily }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(kind.title, systemImage: kind.symbol).font(family == .systemSmall ? .subheadline.bold() : .headline).lineLimit(1)
            if let snapshot = entry.snapshot {
                switch kind {
                case .status: status(snapshot)
                case .next: next(snapshot)
                case .travel: travel(snapshot)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    if snapshot.isStale(at: entry.date) { Image(systemName: "exclamationmark.triangle"); Text("Out of date") }
                    else { Text("Updated") }
                    Text(snapshot.updatedAt, style: .time)
                }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Spacer()
                Text(WidgetSnapshotStore.groupID == nil ? "Widgets require a build signed with an Apple Developer team." : "Open MacTorn and connect your Torn account.").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: "mactorn://\(kind == .travel ? "travel" : "status")"))
    }
    private func status(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(s.status).font(.caption).foregroundStyle(.secondary)
            if s.meters.isEmpty { Text("Bars unavailable").font(.caption) }
            ForEach(s.meters) { meter in
                HStack {
                    Text(meter.name).frame(width: 44, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(color(meter.name).opacity(0.12))
                            Capsule().fill(color(meter.name).opacity(0.4))
                                .frame(width: geometry.size.width * meter.fraction)
                        }
                        .overlay {
                            if family == .systemSmall {
                                Text("\(meter.current)/\(meter.maximum)")
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .monospacedDigit().minimumScaleFactor(0.8)
                            }
                        }
                    }.frame(height: 13)
                    if family != .systemSmall { Text("\(meter.current)/\(meter.maximum)").monospacedDigit() }
                }.font(.caption2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(meter.name), \(meter.current) of \(meter.maximum)")
            }
        }
    }
    private func next(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 16 : 8) {
            let events = Array(s.upcoming(at: entry.date).prefix(family == .systemLarge ? 5 : 3))
            if events.isEmpty { Text("No upcoming timers. Open MacTorn for the latest status.").font(.callout).foregroundStyle(.secondary) }
            ForEach(events) { event in
                HStack {
                    Label(event.title, systemImage: event.symbol).lineLimit(1)
                    Spacer(minLength: 4)
                    if event.date <= entry.date { Text("Ready") }
                    else { Text(timerInterval: entry.date...event.date, countsDown: true).monospacedDigit().multilineTextAlignment(.trailing).frame(width: 85) }
                }.font(.caption)
            }
        }
    }
    private func travel(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.destination ?? "Location unavailable").font(.title3.bold()).lineLimit(1)
            if let arrival = s.arrival {
                if arrival > entry.date {
                    Text(timerInterval: entry.date...arrival, countsDown: true).font(.title2.monospacedDigit())
                    if let departure = s.departure, departure < arrival {
                        #if WIDGET_GALLERY
                        GeometryReader { geometry in
                            Capsule().fill(.blue.opacity(0.15)).overlay(alignment: .leading) {
                                Capsule().fill(.blue).frame(width: geometry.size.width * (s.flightProgress(at: entry.date) ?? 0))
                            }
                        }.frame(height: 4)
                        #else
                        ProgressView(timerInterval: departure...arrival, countsDown: false)
                            .progressViewStyle(.linear).labelsHidden().tint(.blue)
                        #endif
                    }
                    HStack { Text("Arrival"); Text(arrival, style: .time) }.font(.caption)
                } else { Text("Arrival time reached. Open MacTorn to confirm.").font(.caption) }
            } else { Text("Not flying").font(.callout).foregroundStyle(.secondary) }
        }
    }
    private func color(_ name: String) -> Color {
        switch name { case "Energy": .green; case "Nerve": .red; case "Happy": .orange; default: .blue }
    }
}
struct PlayerStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacTorn.status", provider: TornProvider()) { TornWidgetView(entry: $0, kind: .status) }
            .configurationDisplayName("Player Status").description("Energy, Nerve, Happy, Life and your location.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct NextActionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacTorn.next", provider: TornProvider()) { TornWidgetView(entry: $0, kind: .next) }
            .configurationDisplayName("What's Next?").description("Your next timers at a glance.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct TravelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacTorn.travel", provider: TornProvider()) { TornWidgetView(entry: $0, kind: .travel) }
            .configurationDisplayName("Travel").description("Destination, flight progress and arrival countdown.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
#if !WIDGET_GALLERY
@main
struct MacTornWidgetBundle: WidgetBundle {
    var body: some Widget { PlayerStatusWidget(); NextActionWidget(); TravelWidget() }
}

#endif
