import Foundation
import os.log

extension AppState {
    private static var stocksMetadataCacheKey: String { "stocksMetadataCache" }

    // MARK: - Stocks Metadata

    func loadStocksMetadataFromCache() {
        guard let data = defaults.data(forKey: Self.stocksMetadataCacheKey) else { return }
        guard let cached = try? JSONDecoder().decode([Int: StockMetadata].self, from: data) else {
            defaults.removeObject(forKey: Self.stocksMetadataCacheKey)
            stocksMetadata = [:]
            return
        }
        stocksMetadata = cached
    }

    func triggerStocksMetadataFetchIfNeeded() {
        guard stocksMetadata.isEmpty, !apiKey.isEmpty, stocksBackoff.allows(at: time.now),
              !requester.isInFlight("torn.stocks") else { return }
        accountSession.startTask(.stockMetadata) { await self.fetchStocksMetadata() }
    }

    func fetchStocksMetadata() async {
        await fetchReferenceData("torn.stocks", cacheKey: Self.stocksMetadataCacheKey,
                                 parse: { Self.parseStocksMetadata(json: $0, logger: $1) },
                                 onFailure: { stocksBackoff.fail(at: time.now) }) { parsed in
            stocksMetadata = parsed
            stocksBackoff.succeed()
        }
    }

    /// One request per reference source at a time. The parsed map is cached in defaults
    /// before it is published, so the next launch starts from it.
    func fetchReferenceData<Value: Codable & Sendable>(
        _ endpointID: String,
        cacheKey: String,
        parse: @escaping @Sendable ([String: Any], Logger) -> [Int: Value],
        onFailure: () -> Void,
        publish: ([Int: Value]) -> Void
    ) async {
        guard !requester.isInFlight(endpointID) else { return }
        let result = await requester.fetch(endpointID) { _, json -> ([Int: Value], Data)? in
            let parsed = parse(json, Self.appReferenceLogger)
            guard !parsed.isEmpty, let encoded = try? JSONEncoder().encode(parsed) else { return nil }
            return (parsed, encoded)
        }
        switch result {
        case .loaded(let (parsed, encoded)):
            defaults.set(encoded, forKey: cacheKey)
            publish(parsed)
        case .failed:
            onFailure()
        case .nothingToServe, .skipped, .superseded:
            break
        }
    }

    nonisolated private static let appReferenceLogger =
        Logger(subsystem: TornConstants.logSubsystem, category: "ReferenceData")

    nonisolated static func parseStocksMetadata(from data: Data, logger: Logger) -> [Int: StockMetadata] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Stocks metadata: failed to parse JSON")
            return [:]
        }
        return parseStocksMetadata(json: json, logger: logger)
    }

    nonisolated private static func parseStocksMetadata(json: [String: Any], logger: Logger) -> [Int: StockMetadata] {
        if tornAPIErrorMessage(in: json) != nil {
            logger.error("Stocks metadata API returned an error envelope")
            return [:]
        }
        guard let stocksDict = json["stocks"] as? [String: [String: Any]] else {
            logger.warning("Stocks metadata: no 'stocks' key in response")
            return [:]
        }
        var result: [Int: StockMetadata] = [:]
        for (key, stockData) in stocksDict {
            guard let id = Int(key) else { continue }
            let name = stockData["name"] as? String ?? ""
            let acronym = stockData["acronym"] as? String ?? ""
            let price: Double
            if let n = stockData["current_price"] as? NSNumber {
                price = n.doubleValue
            } else if let s = stockData["current_price"] as? String, let d = Double(s) {
                price = d
            } else {
                price = 0
            }
            guard StockMetadata.isValidPrice(price) else { return [:] }
            result[id] = StockMetadata(id: id, name: name, acronym: acronym, currentPrice: price)
        }
        return result
    }

    // MARK: - Notification Rules

    func loadNotificationRules() {
        if let data = defaults.data(forKey: "notificationRules"),
           let rules = try? JSONDecoder().decode([NotificationRule].self, from: data) {
            notificationRules = rules
        } else {
            notificationRules = NotificationRule.defaults
            saveNotificationRules()
        }
    }

    func saveNotificationRules() {
        if let data = try? JSONEncoder().encode(notificationRules) {
            defaults.set(data, forKey: "notificationRules")
        }
    }

    func updateRule(_ rule: NotificationRule) {
        if let index = notificationRules.firstIndex(where: { $0.id == rule.id }) {
            notificationRules[index] = rule
            saveNotificationRules()
        }
    }

    // MARK: - Travel Notification Settings

    func loadTravelNotificationSettings() {
        if let data = defaults.data(forKey: "travelNotificationSettings"),
           let settings = try? JSONDecoder().decode([TravelNotificationSetting].self, from: data) {
            travelNotificationSettings = settings
        } else {
            travelNotificationSettings = TravelNotificationSetting.defaults
            saveTravelNotificationSettings()
        }
    }

    func saveTravelNotificationSettings() {
        if let data = try? JSONEncoder().encode(travelNotificationSettings) {
            defaults.set(data, forKey: "travelNotificationSettings")
        }
    }

    func updateTravelNotificationSetting(_ setting: TravelNotificationSetting) {
        if let index = travelNotificationSettings.firstIndex(where: { $0.id == setting.id }) {
            travelNotificationSettings[index] = setting
            saveTravelNotificationSettings()
            if let travel = player.data?.travel, travel.isTraveling {
                scheduleTravelNotifications(for: travel)
            }
        }
    }

    func cancelLandingAlerts() {
        notifier.cancelPending(identifiers: TravelNotificationSetting.defaults.map(\.notificationIdentifier))
    }

    func scheduleTravelNotifications(for travel: Travel) {
        cancelLandingAlerts()

        // `travel.timestamp` is an absolute *server* timestamp, but a scheduled local
        // notification fires on the *Mac's* clock — so convert back through the skew
        // (issue #46), or a 90 s-slow Mac fires every landing alert 90 s early.
        guard travel.isTraveling, let arrival = travel.timestamp, arrival > 0 else { return }
        let arrivalDate = player.serverClock.localDate(forServerTimestamp: arrival)

        for setting in travelNotificationSettings where setting.enabled {
            let notificationDate = arrivalDate.addingTimeInterval(-Double(setting.secondsBefore))

            if notificationDate > time.now {
                let identifier = setting.notificationIdentifier
                let timeText: String
                if setting.secondsBefore >= 60 {
                    timeText = "\(setting.secondsBefore / 60) minute\(setting.secondsBefore >= 120 ? "s" : "")"
                } else {
                    timeText = "\(setting.secondsBefore) seconds"
                }

                notifier.schedule(
                    title: "Landing Soon!",
                    body: "You will arrive in \(travel.destination ?? "your destination") in \(timeText)",
                    type: .travelApproaching,
                    at: notificationDate,
                    identifier: identifier
                )
            }
        }
    }
}
