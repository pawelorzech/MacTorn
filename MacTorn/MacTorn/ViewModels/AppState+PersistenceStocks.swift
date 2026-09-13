import Foundation
import os.log

extension AppState {
    private static var stocksMetadataCacheKey: String { "stocksMetadataCache" }
    private static var stocksBackoffLadder: [TimeInterval] { [60, 300, 1800] }

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

    func fetchStocksMetadata() async {
        await fetchReferenceData("torn.stocks", cacheKey: Self.stocksMetadataCacheKey,
                                 parse: { Self.parseStocksMetadata(json: $0, logger: $1) },
                                 onFailure: recordStocksMetadataFailure) { parsed in
            stocksMetadata = parsed
            stocksFailureCount = 0
            stocksNextRetryAfter = nil
        }
    }

    /// One in-flight request per reference source, with publication owned by its account
    /// and token. An old completion cannot clear or mutate a newer request.
    func fetchReferenceData<Value: Codable & Sendable>(
        _ endpointID: String,
        cacheKey: String,
        parse: @escaping @Sendable ([String: Any], Logger) -> [Int: Value],
        onFailure: () -> Void,
        publish: ([Int: Value]) -> Void
    ) async {
        guard !Task.isCancelled, referenceFetchIDs[endpointID] == nil,
              !apiKey.isEmpty, let url = endpointURL(endpointID),
              reserveRequest(endpointID) else { return }
        let identity = accountSession.identity
        let token = UUID()
        referenceFetchIDs[endpointID] = token
        defer {
            if referenceFetchIDs[endpointID] == token { referenceFetchIDs[endpointID] = nil }
        }
        let started = Date()
        do {
            let result: TornServiceResult<([Int: Value], Data)> = try await TornAPIClient.loadJSON(from: url, session: session) { _, json in
                let parsed = parse(json, Self.appReferenceLogger)
                guard !parsed.isEmpty, let encoded = try? JSONEncoder().encode(parsed) else { return nil }
                return (parsed, encoded)
            }
            guard !Task.isCancelled, accountSession.isCurrent(identity),
                  referenceFetchIDs[endpointID] == token else { return }
            if case .success(let (parsed, encoded), let bytes) = result {
                defaults.set(encoded, forKey: cacheKey)
                publish(parsed)
                endpointGate.noteSuccess(for: endpointID)
                recordHealth(endpointID, outcome: .ok, since: started, bytes: bytes)
            } else {
                onFailure()
                recordServiceFailure(result, for: endpointID, since: started)
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                  accountSession.isCurrent(identity), referenceFetchIDs[endpointID] == token,
                  (error as? URLError)?.code != .cancelled else { return }
            onFailure()
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            recordHealth(endpointID, outcome: mapped?.classification == .offline ? .offline : .error,
                         since: started, bytes: 0, errorClass: mapped?.classification.rawValue ?? "transport")
        }
    }

    nonisolated private static let appReferenceLogger =
        Logger(subsystem: TornConstants.logSubsystem, category: "ReferenceData")

    @MainActor
    func recordStocksMetadataFailure() {
        stocksFailureCount += 1
        let idx = min(stocksFailureCount - 1, Self.stocksBackoffLadder.count - 1)
        let delay = Self.stocksBackoffLadder[idx]
        stocksNextRetryAfter = time.now.addingTimeInterval(delay)
    }

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
            if let travel = data?.travel, travel.isTraveling {
                scheduleTravelNotifications(for: travel)
            }
        }
    }

    func scheduleTravelNotifications(for travel: Travel) {
        NotificationManager.shared.cancelTravelNotifications()

        // `travel.timestamp` is an absolute *server* timestamp, but a scheduled local
        // notification fires on the *Mac's* clock — so convert back through the skew
        // (issue #46), or a 90 s-slow Mac fires every landing alert 90 s early.
        guard travel.isTraveling, let arrival = travel.timestamp, arrival > 0 else { return }
        let arrivalDate = serverClock.localDate(forServerTimestamp: arrival)

        for setting in travelNotificationSettings where setting.enabled {
            let notificationDate = arrivalDate.addingTimeInterval(-Double(setting.secondsBefore))

            if notificationDate > time.now {
                let identifier = "\(setting.id)_alert"
                let timeText: String
                if setting.secondsBefore >= 60 {
                    timeText = "\(setting.secondsBefore / 60) minute\(setting.secondsBefore >= 120 ? "s" : "")"
                } else {
                    timeText = "\(setting.secondsBefore) seconds"
                }

                NotificationManager.shared.scheduleNotification(
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
