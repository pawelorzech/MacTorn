import Foundation
import WidgetKit

extension AppState {
    func makeWidgetSnapshot() -> WidgetSnapshot? {
        guard let data else { return nil }
        func localDate(_ timestamp: Int) -> Date {
            Date(timeIntervalSince1970: TimeInterval(timestamp - serverClock.offset))
        }
        let meters = data.bars.map { bars in
            [("Energy", bars.energy), ("Nerve", bars.nerve), ("Happy", bars.happy), ("Life", bars.life)]
                .map { WidgetSnapshot.Meter(name: $0.0, current: $0.1.current, maximum: $0.1.maximum) }
        } ?? []
        let next = makeNextActionSnapshot(now: time.now)
        let events = NextActionEngine().events(from: next, hidden: hiddenNextActionCategories.union([.chain]))
            .map { WidgetSnapshot.Event(id: $0.id, title: $0.title, symbol: $0.systemImage, date: localDate($0.fireAt)) }
        let status: String
        if data.status?.isInHospital == true { status = "Hospital" }
        else if data.status?.isInJail == true { status = "Jail" }
        else if data.travel?.isTraveling == true { status = "Traveling" }
        else { status = data.travel?.destination ?? "Torn" }
        return WidgetSnapshot(updatedAt: lastFetchTime, meters: meters, status: status,
            destination: data.travel?.destination,
            departure: data.travel?.departed.flatMap { $0 > 0 ? localDate($0) : nil },
            arrival: next.travelArrivalAt.map(localDate), events: events)
    }

    func publishWidgets() {
        guard let widgetStore, let snapshot = makeWidgetSnapshot() else { return }
        do {
            try widgetStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { logger.error("Could not save widget display data") }
    }

    func clearWidgets() {
        guard let widgetStore else { return }
        do { try widgetStore.clear() }
        catch { logger.error("Could not clear widget display data") }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
