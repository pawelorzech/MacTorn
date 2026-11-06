import SwiftUI

/// Only display data crosses the process boundary. Never persist the API key here.
struct WidgetSnapshot: Codable, Equatable {
    struct Meter: Codable, Equatable, Identifiable {
        /// The four player bars, in display order. The raw value is the name written into
        /// the snapshot, so files from older builds (which stored only `name`) still map.
        enum Kind: String, CaseIterable {
            case energy = "Energy"
            case nerve = "Nerve"
            case happy = "Happy"
            case life = "Life"

            var name: String { rawValue }
            var color: Color {
                switch self {
                case .energy: .green
                case .nerve: .red
                case .happy: .yellow
                case .life: .blue
                }
            }
            var icon: String {
                switch self {
                case .energy: "bolt.fill"
                case .nerve: "flame.fill"
                case .happy: "face.smiling.fill"
                case .life: "heart.fill"
                }
            }
        }

        var id: String { name }
        let name: String
        let current: Int
        let maximum: Int
        var fraction: Double { min(1, max(0, Double(current) / Double(max(1, maximum)))) }
        var kind: Kind? { Kind(rawValue: name) }

        init(name: String, current: Int, maximum: Int) {
            self.name = name
            self.current = current
            self.maximum = maximum
        }

        init(_ kind: Kind, current: Int, maximum: Int) {
            self.init(name: kind.name, current: current, maximum: maximum)
        }
    }
    struct Event: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let symbol: String
        let date: Date
        /// Stays in the list after `date` has passed (a ready refill is still worth showing).
        var persistsPastDate = false
    }
    let updatedAt: Date
    let meters: [Meter]
    let status: String
    let destination: String?
    let departure: Date?
    let arrival: Date?
    let events: [Event]

    /// After this long without a fresh snapshot the widget says its data is old.
    static let staleAfter: TimeInterval = 300

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(updatedAt) > Self.staleAfter }
    func upcoming(at now: Date) -> [Event] {
        events.filter { $0.date > now || $0.persistsPastDate }.sorted { $0.date < $1.date }
    }
    static let preview = WidgetSnapshot(updatedAt: Date(), meters: [
        .init(.energy, current: 110, maximum: 150),
        .init(.nerve, current: 32, maximum: 60),
        .init(.happy, current: 4200, maximum: 5000),
        .init(.life, current: 3500, maximum: 4000)
    ], status: "Traveling", destination: "Japan", departure: Date().addingTimeInterval(-3600),
        arrival: Date().addingTimeInterval(1800), events: [
            .init(id: "travel", title: "Landing", symbol: "airplane.arrival", date: Date().addingTimeInterval(1800)),
            .init(id: "energy", title: "Energy full", symbol: "bolt.fill", date: Date().addingTimeInterval(2400)),
            .init(id: "drug", title: "Drug ready", symbol: "pills.fill", date: Date().addingTimeInterval(5400))
        ])
}

/// In an extension so `Event` keeps its memberwise initializer. Snapshots written before
/// `persistsPastDate` existed have no such key.
extension WidgetSnapshot.Event {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(String.self, forKey: .id),
                  title: try container.decode(String.self, forKey: .title),
                  symbol: try container.decode(String.self, forKey: .symbol),
                  date: try container.decode(Date.self, forKey: .date),
                  persistsPastDate: try container.decodeIfPresent(Bool.self, forKey: .persistsPastDate) ?? false)
    }
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
