import Foundation
import Combine

/// Price alerts latched during one watchlist refresh run, announced together when it ends.
@MainActor
final class PriceAlertBatch {
    var alerts: [MarketPriceAlert] = []
}

extension AppState {
    /// Why an Item ID typed into the watchlist panel was rejected.
    enum WatchlistAddOutcome: Equatable {
        case added(itemId: Int)
        /// Empty, non-numeric, zero or negative.
        case notANumber
        /// Numeric and positive, but outside the range Torn item ids occupy.
        case outOfRange(maximum: Int)
        case alreadyWatched
    }

    /// Adds an item and prices it straight away. `false` when it was rejected (already
    /// watched, or an invalid id), so the add panel can stay open and say so.
    @discardableResult
    func addToWatchlist(itemId: Int, name: String) -> Bool {
        guard watchlist.add(itemID: itemId, name: name) else {
            logger.warning("addToWatchlist rejected invalid or duplicate item \(itemId)")
            return false
        }
        Task { await fetchPrices(for: watchlist.items.filter { $0.id == itemId }) }
        return true
    }

    /// Adds an item typed by id. The name is the catalogue's, or a placeholder the
    /// catalogue backfills later.
    func addToWatchlist(input: String) -> WatchlistAddOutcome {
        guard let itemId = PositiveIntegerInput.value(from: input) else { return .notANumber }
        guard itemId < MarketWatchService.maximumItemID else {
            return .outOfRange(maximum: MarketWatchService.maximumItemID)
        }
        guard !watchlist.items.contains(where: { $0.id == itemId }) else {
            return .alreadyWatched
        }
        guard addToWatchlist(itemId: itemId, name: itemName(for: itemId)) else { return .notANumber }
        return .added(itemId: itemId)
    }

    func refreshWatchlistPrices() {
        accountSession.startTask(.watchlist) {
            await self.fetchPrices(for: self.watchlist.items)
        }
    }

    /// Prices every item Torn has re-cached since its last read, four at a time. Alerts
    /// are announced and the list saved once, at the end of the run — deliberately even
    /// when a newer refresh superseded this one, because `apply` has already spent each
    /// alert's epoch. Only an account change voids them.
    private func fetchPrices(for items: [WatchlistItem]) async {
        guard canTalkToTorn else { return }
        let identity = accountSession.identity
        let now = time.now
        let due = items.filter { item in
            guard let timestamp = item.dataTimestamp, let delay = item.cacheDelay else { return true }
            return timestamp.addingTimeInterval(delay) <= now
        }.map(\.id)
        let batch = PriceAlertBatch()
        await BoundedTaskQueue.run(due, limit: 4) { [weak self] itemID in
            await self?.fetchPrice(itemID: itemID, into: batch)
        }
        guard accountSession.isCurrent(identity) else { return }
        postPriceAlerts(batch.alerts)
        watchlist.save()
    }

    private func fetchPrice(itemID: Int, into batch: PriceAlertBatch) async {
        switch await requester.fetch("market.item", parameter: itemID, decode: MarketWatchService.decodePrice) {
        case .loaded(let snapshot?):
            if let alert = watchlist.apply(snapshot.localized(using: player.serverClock), to: itemID) {
                batch.alerts.append(alert)
            }
        case .loaded(nil):
            watchlist.setError("No listings", for: itemID)
        case .failed(let failure):
            watchlist.setError(failure.userMessage, for: itemID)
        case .skipped(let denial?):
            watchlist.setError(denial.userExplanation, for: itemID)
        case .skipped(nil), .nothingToServe, .superseded:
            break
        }
    }

    /// One banner for a single alert, a summary for several.
    func postPriceAlerts(_ alerts: [MarketPriceAlert]) {
        guard let first = alerts.first else { return }
        if alerts.count == 1 {
            notifier.send(title: "Price Alert: \(first.name)",
                          body: "Lowest price dropped to \(TornFormatter.formatMoney(first.price))",
                          type: .priceAlert)
            return
        }
        let preview = alerts.prefix(3).map(\.name).joined(separator: ", ")
        let extra = alerts.count > 3 ? " +\(alerts.count - 3) more" : ""
        notifier.send(title: "\(alerts.count) price alerts", body: "\(preview)\(extra)", type: .priceAlert)
    }

    /// Sets or clears an item's alert threshold. A new threshold re-arms the alert.
    func setWatchlistThreshold(_ threshold: Int?, for itemId: Int) {
        guard let index = watchlist.items.firstIndex(where: { $0.id == itemId }) else { return }
        watchlist.items[index].priceThreshold = threshold
        watchlist.items[index].lastAlertedPrice = nil
        watchlist.save()
    }

    /// Puts back a cleared threshold exactly as it was, for the Undo banner.
    @discardableResult
    func restoreWatchlistThreshold(itemId: Int, threshold: Int?, lastAlertedPrice: Int?) -> Bool {
        guard let index = watchlist.items.firstIndex(where: { $0.id == itemId }) else { return false }
        watchlist.items[index].priceThreshold = threshold
        watchlist.items[index].lastAlertedPrice = lastAlertedPrice
        watchlist.save()
        return true
    }

    // MARK: - Background price alerts

    /// Torn caches item-market data for about this long anyway, and `cacheDelay` skips
    /// anything not yet re-cached.
    static let priceAlertPollInterval: TimeInterval = 300

    var hasPriceThresholds: Bool {
        watchlist.items.contains { $0.priceThreshold != nil }
    }

    /// The price-alert timer runs only while user polling does and at least one item has a
    /// threshold, so a watchlist with no alerts spends nothing.
    func syncPriceAlertPolling() {
        guard pollTimer.isRunning, !keyHalted, !apiKey.isEmpty, hasPriceThresholds else {
            stopPriceAlertPolling()
            return
        }
        guard !priceAlertTimer.isRunning else { return }
        priceAlertTimer.start(every: Self.priceAlertPollInterval) { [weak self] in
            self?.refreshPriceAlerts()
        }
    }

    func stopPriceAlertPolling() {
        priceAlertTimer.stop()
    }

    func refreshPriceAlerts() {
        guard !keyHalted, hasPriceThresholds else { return }
        accountSession.startTask(.priceAlerts) {
            await self.fetchPrices(for: self.watchlist.items.filter { $0.priceThreshold != nil })
        }
    }
}
