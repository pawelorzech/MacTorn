import Foundation

/// Only display data crosses the process boundary. Never persist the API key here.
struct WidgetSnapshot: Codable, Equatable {
    struct Meter: Codable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        let current: Int
        let maximum: Int
        var fraction: Double { min(1, max(0, Double(current) / Double(max(1, maximum)))) }
    }
    struct Event: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let symbol: String
        let date: Date
    }
    let updatedAt: Date
    let meters: [Meter]
    let status: String
    let destination: String?
    let departure: Date?
    let arrival: Date?
    let events: [Event]

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(updatedAt) > 300 }
    func upcoming(at now: Date) -> [Event] {
        events.filter { $0.date > now || $0.id == "refills" }.sorted { $0.date < $1.date }
    }
    func flightProgress(at now: Date) -> Double? {
        guard let departure, let arrival, arrival > departure else { return nil }
        return min(1, max(0, now.timeIntervalSince(departure) / arrival.timeIntervalSince(departure)))
    }
    static let preview = WidgetSnapshot(updatedAt: Date(), meters: [
        .init(name: "Energy", current: 110, maximum: 150),
        .init(name: "Nerve", current: 32, maximum: 60),
        .init(name: "Happy", current: 4200, maximum: 5000),
        .init(name: "Life", current: 3500, maximum: 4000)
    ], status: "Traveling", destination: "Japan", departure: Date().addingTimeInterval(-3600),
        arrival: Date().addingTimeInterval(1800), events: [
            .init(id: "travel", title: "Landing", symbol: "airplane.arrival", date: Date().addingTimeInterval(1800)),
            .init(id: "energy", title: "Energy full", symbol: "bolt.fill", date: Date().addingTimeInterval(2400)),
            .init(id: "drug", title: "Drug ready", symbol: "pills.fill", date: Date().addingTimeInterval(5400))
        ])
}

struct WidgetSnapshotStore {
    static var groupID: String? {
        guard Bundle.main.object(forInfoDictionaryKey: "MacTornWidgetEntitlementsSuffix") as? String == ".widgets",
              let value = Bundle.main.object(forInfoDictionaryKey: "MacTornWidgetGroup") as? String,
              !value.hasPrefix("."), !value.contains("$("), !value.isEmpty else { return nil }
        return value
    }
    let directory: URL?
    init(directory: URL?) { self.directory = directory }
    static var shared: Self {
        Self(directory: groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) })
    }
    private var file: URL? { directory?.appendingPathComponent("widget-snapshot.json") }
    func read() -> WidgetSnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
    func write(_ snapshot: WidgetSnapshot) throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
    func clear() throws {
        guard let file else { return }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
