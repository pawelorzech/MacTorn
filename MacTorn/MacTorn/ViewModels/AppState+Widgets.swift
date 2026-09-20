import Foundation

extension AppState {
    func makeWidgetSnapshot() -> WidgetSnapshot? {
        guard let data else { return nil }
        // Server→local conversion lives on `ServerClock`; this used to re-derive it by hand
        // (audit D-8).
        func localDate(_ timestamp: Int) -> Date {
            serverClock.localDate(forServerTimestamp: timestamp)
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
        guard widgetStore != nil, data != nil, widgetPublicationTask == nil else { return }
        // Batch a burst of endpoint completions without waiting for slower siblings.
        widgetPublicationTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.widgetPublicationTask = nil
            self.writeWidgetSnapshot()
        }
    }

    private func writeWidgetSnapshot() {
        guard let widgetStore, let snapshot = makeWidgetSnapshot() else { return }
        do {
            try widgetStore.write(snapshot)
            reloadWidgetTimelines()
        } catch { logger.error("Could not save widget display data") }
    }

    func clearWidgets() {
        widgetPublicationTask?.cancel()
        widgetPublicationTask = nil
        guard let widgetStore else { return }
        do { try widgetStore.clear() }
        catch { logger.error("Could not clear widget display data") }
        reloadWidgetTimelines()
    }
}