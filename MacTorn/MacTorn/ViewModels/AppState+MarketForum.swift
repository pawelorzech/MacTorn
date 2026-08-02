import Foundation
import Combine

extension AppState {
    // MARK: - Watchlist

    func loadWatchlist() {
        marketWatchService.load()
    }

    func saveWatchlist() {
        marketWatchService.save()
    }

    /// Adds an item to the price watchlist.
    ///
    /// Returns `false` when the item was rejected (already watched, or an invalid id).
    /// The result is deliberately part of the contract: the add panel used to close on
    /// every tap regardless of outcome, so tapping an item that was already on the list
    /// looked exactly like success — the panel vanished and nothing changed.
    @discardableResult
    func addToWatchlist(itemId: Int, name: String) -> Bool {
        guard marketWatchService.add(itemID: itemId, name: name) else {
            logger.warning("addToWatchlist rejected invalid or duplicate item \(itemId)")
            return false
        }
        Task {
            await fetchItemPrice(itemId: itemId)
        }
        return true
    }

    func removeFromWatchlist(_ itemId: Int) {
        marketWatchService.remove(itemID: itemId)
    }

    /// Parses the raw text from the watchlist's Item ID field. Mirrors
    /// `parseThreadInput` — numeric, positive only.
    func parseItemIdInput(_ input: String) -> Int? {
        PositiveIntegerInput.value(from: input)
    }

    /// Why an Item ID typed into the watchlist panel was rejected.
    ///
    /// `addToWatchlist(input:)` used to answer this with a bare `Bool`, which left the
    /// UI unable to tell "out of range" from "duplicate" — so an id of 200000 was
    /// reported to the user as "already on your watchlist", which was simply untrue.
    enum WatchlistAddOutcome: Equatable {
        case added(itemId: Int)
        /// Empty, non-numeric, zero or negative.
        case notANumber
        /// Numeric and positive, but outside the range Torn item ids occupy.
        case outOfRange(maximum: Int)
        case alreadyWatched
    }

    /// Adds a watchlist item from raw text input. There is no local item-name
    /// database (unlike forum threads, whose titles come back from the API on the
    /// first fetch), so this seeds a placeholder name; `fetchItemPrice` only ever
    /// updates price fields, never the name.
    func addToWatchlist(input: String) -> WatchlistAddOutcome {
        guard let itemId = parseItemIdInput(input) else { return .notANumber }
        guard itemId < MarketWatchService.maximumItemID else {
            return .outOfRange(maximum: MarketWatchService.maximumItemID)
        }
        guard !watchlistItems.contains(where: { $0.id == itemId }) else {
            return .alreadyWatched
        }
        guard addToWatchlist(itemId: itemId, name: "Item #\(itemId)") else {
            // The service applies the same bounds we just checked, so reaching here
            // means those two definitions drifted apart.
            logger.error("addToWatchlist(input:) passed its own checks but the service still rejected \(itemId)")
            return .notANumber
        }
        return .added(itemId: itemId)
    }

    func refreshWatchlistPrices() {
        accountSession.startTask(.watchlist) {
            await self.fetchWatchlistPrices()
        }
    }

    private func fetchWatchlistPrices() async {
        guard connectivity.isConnected else { return }
        let requestedKey = apiKey
        let generation = accountSession.identity.generation
        guard !requestedKey.isEmpty else { return }
        let itemIDs = watchlistItems.map(\.id)
        pendingPriceAlerts.removeAll(keepingCapacity: true)
        await BoundedTaskQueue.run(itemIDs, limit: 4) { [weak self] itemID in
            guard let self else { return }
            await self.fetchItemPrice(
                itemId: itemID,
                apiKey: requestedKey,
                generation: generation,
                save: false
            )
        }
        guard !Task.isCancelled,
              isCurrentAccount(requestedKey, generation: generation) else { return }
        flushPendingPriceAlerts()
        saveWatchlist()
    }

    private func flushPendingPriceAlerts() {
        let alerts = pendingPriceAlerts
        pendingPriceAlerts.removeAll(keepingCapacity: true)
        guard !alerts.isEmpty else { return }
        if alerts.count == 1 {
            let a = alerts[0]
            NotificationManager.shared.send(
                title: "Price Alert: \(a.name)",
                body: "Lowest price dropped to \(formatAlertPrice(a.price))",
                type: .priceAlert
            )
            return
        }
        // Summary notification: list up to 3 names then "+N more".
        let preview = alerts.prefix(3).map { $0.name }.joined(separator: ", ")
        let extra = alerts.count > 3 ? " +\(alerts.count - 3) more" : ""
        NotificationManager.shared.send(
            title: "\(alerts.count) price alerts",
            body: "\(preview)\(extra)",
            type: .priceAlert
        )
    }

    private func fetchItemPrice(itemId: Int, save: Bool = true) async {
        let requestedKey = apiKey
        let generation = accountSession.identity.generation
        await fetchItemPrice(
            itemId: itemId,
            apiKey: requestedKey,
            generation: generation,
            save: save
        )
    }

    private func fetchItemPrice(
        itemId: Int,
        apiKey requestedKey: String,
        generation: UInt,
        save: Bool
    ) async {
        guard isCurrentAccount(requestedKey, generation: generation),
              !requestedKey.isEmpty,
              let url = TornAPI.marketURL(itemId: itemId, apiKey: requestedKey) else { return }
        guard reserveRequest("market.item") else {
            updateItemError(itemId: itemId, error: "Request limit reached", save: save)
            return
        }

        logger.info("Fetching price for item \(itemId)")

        do {
            let result = try await marketWatchService.fetchPrice(from: url)
            guard !Task.isCancelled,
                  isCurrentAccount(requestedKey, generation: generation) else { return }

            switch result {
            case .success(let snapshot, _):
                updateItemPrice(
                    itemId: itemId,
                    lowestPrice: snapshot.lowestPrice,
                    lowestPriceQuantity: snapshot.lowestPriceQuantity,
                    secondLowestPrice: snapshot.secondLowestPrice,
                    save: save
                )
            case .apiError(let apiError, _):
                logger.warning("Item \(itemId) API returned an error envelope")
                updateItemError(itemId: itemId, error: apiError.userMessage, save: save)
            case .httpError(let statusCode, _):
                logger.error("Item \(itemId) HTTP Error: \(statusCode)")
                updateItemError(itemId: itemId, error: "HTTP \(statusCode)", save: save)
            case .noListings:
                updateItemError(itemId: itemId, error: "No listings", save: save)
            case .malformed:
                logger.error("Item \(itemId): failed to parse JSON response")
                updateItemError(itemId: itemId, error: "Parse Error", save: save)
            }
        } catch {
            guard !Task.isCancelled,
                  isCurrentAccount(requestedKey, generation: generation) else { return }
            logger.error("Item \(itemId) price fetch error: \(String(describing: type(of: error)))")
            updateItemError(itemId: itemId, error: "Network Error", save: save)
        }
    }

    @MainActor
    private func updateItemPrice(itemId: Int, lowestPrice: Int, lowestPriceQuantity: Int, secondLowestPrice: Int, save: Bool = true) {
        let snapshot = MarketPriceSnapshot(
            lowestPrice: lowestPrice,
            lowestPriceQuantity: lowestPriceQuantity,
            secondLowestPrice: secondLowestPrice
        )
        if let alert = marketWatchService.apply(snapshot, to: itemId) {
            if save {
                NotificationManager.shared.send(
                    title: "Price Alert: \(alert.name)",
                    body: "Lowest price dropped to \(formatAlertPrice(alert.price))",
                    type: .priceAlert
                )
            } else {
                pendingPriceAlerts.append((name: alert.name, price: alert.price))
            }
        }
        if save { marketWatchService.save() }
    }

    private func formatAlertPrice(_ price: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: price)) ?? "$\(price)"
    }

    @MainActor
    private func updateItemError(itemId: Int, error: String, save: Bool = true) {
        marketWatchService.setError(error, for: itemId)
        if save { marketWatchService.save() }
    }

    // MARK: - Forum Watch

    func loadForumWatch() {
        forumWatchService.load()
    }

    func saveForumWatch() {
        forumWatchService.save()
    }

    func parseThreadInput(_ input: String) -> Int? {
        forumWatchService.parseThreadInput(input)
    }

    @discardableResult
    func addWatchedThread(input: String) -> Bool {
        guard let threadId = forumWatchService.add(input: input) else { return false }
        Task {
            await fetchForumThreadMetadata(threadId: threadId)
        }
        return true
    }

    func removeWatchedThread(_ threadId: Int) {
        forumWatchService.remove(threadID: threadId)
    }

    func toggleThreadNotifications(_ threadId: Int) {
        forumWatchService.toggleNotifications(threadID: threadId)
    }

    func markThreadAsRead(_ threadId: Int) {
        forumWatchService.markAsRead(threadID: threadId)
    }

    func startForumPolling() {
        // Same MenuBarExtra-onAppear churn as startPolling: skip restart if already
        // running and we polled recently.
        if forumTimerCancellable != nil,
           let last = lastForumFetchAt,
           Date().timeIntervalSince(last) < Double(forumWatchConfig.pollingIntervalSeconds) / 2 {
            return
        }
        forumTimerCancellable?.cancel()
        guard !apiKey.isEmpty else { return }

        // Initial fetch
        refreshForumWatch()

        forumTimerCancellable = Timer.publish(every: Double(forumWatchConfig.pollingIntervalSeconds), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshForumWatch()
            }
    }

    func stopForumPolling() {
        forumTimerCancellable?.cancel()
        forumTimerCancellable = nil
    }

    func refreshForumWatch() {
        accountSession.startTask(.forum) {
            await self.fetchForumUpdates()
        }
    }

    private func fetchForumUpdates() async {
        guard connectivity.isConnected, !apiKey.isEmpty else { return }
        let requestedKey = apiKey
        let generation = accountSession.identity.generation
        let threadIDs = watchedThreads.map(\.id)

        await BoundedTaskQueue.run(threadIDs, limit: 4) { [weak self] threadID in
            guard let self else { return }
            await self.checkThreadForUpdates(
                threadId: threadID,
                apiKey: requestedKey,
                generation: generation
            )
        }

        guard !Task.isCancelled,
              isCurrentAccount(requestedKey, generation: generation) else { return }
        lastForumFetchAt = Date()
        saveForumWatch()
    }

    private func checkThreadForUpdates(
        threadId: Int,
        apiKey requestedKey: String,
        generation: UInt
    ) async {
        guard isCurrentAccount(requestedKey, generation: generation),
              let url = TornAPI.forumThreadURL(threadId: threadId, apiKey: requestedKey) else { return }
        guard reserveRequest("forum.thread") else {
            updateThreadError(threadId: threadId, error: "Request limit reached")
            return
        }

        do {
            let result = try await forumWatchService.fetchThread(from: url)
            guard !Task.isCancelled,
                  isCurrentAccount(requestedKey, generation: generation) else { return }

            switch result {
            case .success(let snapshot, _):
                if let update = forumWatchService.apply(snapshot, to: threadId) {
                    let threadURL = URL(
                        string: "https://www.torn.com/forums.php#/p=threads&t=\(threadId)"
                    )
                    NotificationManager.shared.send(
                        title: "Forum: \(update.title)",
                        body: "\(update.count) new post\(update.count == 1 ? "" : "s")",
                        type: .forumNewPosts,
                        customURL: threadURL
                    )
                }
            case .apiError(let apiError, _):
                updateThreadError(threadId: threadId, error: apiError.userMessage)
            case .httpError, .malformed:
                return
            }
        } catch {
            guard !Task.isCancelled,
                  isCurrentAccount(requestedKey, generation: generation) else { return }
            updateThreadError(threadId: threadId, error: "Network Error")
        }
    }

    @MainActor
    private func updateThreadError(threadId: Int, error: String) {
        forumWatchService.setError(error, for: threadId)
    }

    private func fetchForumThreadMetadata(threadId: Int) async {
        let requestedKey = apiKey
        let generation = accountSession.identity.generation
        guard !requestedKey.isEmpty,
              let url = TornAPI.forumThreadURL(threadId: threadId, apiKey: requestedKey) else { return }
        guard reserveRequest("forum.thread") else {
            updateThreadError(threadId: threadId, error: "Request limit reached")
            return
        }

        do {
            let result = try await forumWatchService.fetchThread(from: url)
            guard !Task.isCancelled,
                  isCurrentAccount(requestedKey, generation: generation) else { return }

            switch result {
            case .success(let snapshot, _):
                _ = forumWatchService.apply(snapshot, to: threadId)
            case .apiError(let apiError, _):
                updateThreadError(threadId: threadId, error: apiError.userMessage)
            case .httpError:
                updateThreadError(threadId: threadId, error: "HTTP Error")
            case .malformed:
                return
            }
        } catch {
            guard !Task.isCancelled,
                  isCurrentAccount(requestedKey, generation: generation) else { return }
            updateThreadError(threadId: threadId, error: "Network Error")
        }

        if isCurrentAccount(requestedKey, generation: generation) {
            saveForumWatch()
        }
    }
}
