import Foundation
import os.log

extension AppState {
    private static var stocksMetadataCacheKey: String { "stocksMetadataCache" }
    private static var stocksBackoffLadder: [TimeInterval] { [60, 300, 1800] }

    // MARK: - Stocks Metadata

    func loadStocksMetadataFromCache() {
        guard let data = defaults.data(forKey: Self.stocksMetadataCacheKey),
              let cached = try? JSONDecoder().decode([Int: StockMetadata].self, from: data) else {
            return
        }
        stocksMetadata = cached
    }

    func fetchStocksMetadata() async {
        guard !apiKey.isEmpty, let url = endpointURL("torn.stocks", key: apiKey) else { return }
        guard reserveRequest("torn.stocks") else { return }
        let startTime = Date()
        do {
            let request = TornAPIClient.request(for: url)
            let (data, _) = try await session.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let apiError = tornAPIError(in: json) {
                await MainActor.run {
                    self.handleAPIError(apiError, for: "torn.stocks")
                    self.recordStocksMetadataFailure()
                    self.recordHealth(
                        "torn.stocks",
                        outcome: .error,
                        since: startTime,
                        bytes: data.count,
                        errorClass: apiError.classification.rawValue
                    )
                }
                return
            }
            let parsed = AppState.parseStocksMetadata(from: data, logger: logger)
            guard !parsed.isEmpty else {
                await MainActor.run {
                    self.recordStocksMetadataFailure()
                    self.recordHealth("torn.stocks", outcome: .error, since: startTime, bytes: data.count, errorClass: "malformedResponse")
                }
                return
            }
            await MainActor.run {
                self.stocksMetadata = parsed
                if let encoded = try? JSONEncoder().encode(parsed) {
                    defaults.set(encoded, forKey: Self.stocksMetadataCacheKey)
                }
                self.stocksFailureCount = 0
                self.stocksNextRetryAfter = nil
                self.endpointGate.noteSuccess(for: "torn.stocks")
                self.recordHealth("torn.stocks", outcome: .ok, since: startTime, bytes: data.count)
                self.logger.info("Stocks metadata loaded: \(parsed.count) stocks")
            }
        } catch {
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            await MainActor.run {
                self.recordStocksMetadataFailure()
                self.recordHealth(
                    "torn.stocks",
                    outcome: mapped?.classification == .offline ? .offline : .error,
                    since: startTime,
                    bytes: 0,
                    errorClass: mapped?.classification.rawValue ?? "transport"
                )
            }
            logger.error("Failed to fetch stocks metadata: \(String(describing: type(of: error)))")
        }
    }

    @MainActor
    func recordStocksMetadataFailure() {
        stocksFailureCount += 1
        let idx = min(stocksFailureCount - 1, Self.stocksBackoffLadder.count - 1)
        let delay = Self.stocksBackoffLadder[idx]
        stocksNextRetryAfter = Date().addingTimeInterval(delay)
    }

    nonisolated static func parseStocksMetadata(from data: Data, logger: Logger) -> [Int: StockMetadata] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Stocks metadata: failed to parse JSON")
            return [:]
        }
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
