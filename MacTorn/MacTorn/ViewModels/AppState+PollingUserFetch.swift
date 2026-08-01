import Foundation
import Combine

extension AppState {
    private static var activityMinInterval: TimeInterval { 300 }
    private static var dailyRowLimitPause: TimeInterval { 3600 }

    // MARK: - Polling

    func startPolling(force: Bool = false) {
        guard !keyHalted else {
            logger.warning("startPolling skipped: polling halted on a permanent key error")
            return
        }
        if !force,
           timerCancellable != nil,
           Date().timeIntervalSince(lastFetchTime) < Double(refreshInterval) / 2 {
            return
        }
        timerCancellable?.cancel()
        fetchData()
        triggerStocksMetadataFetchIfNeeded()
        timerCancellable = Timer.publish(every: Double(refreshInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchData()
                self?.triggerStocksMetadataFetchIfNeeded()
            }
    }

    private func triggerStocksMetadataFetchIfNeeded() {
        guard stocksMetadata.isEmpty, !apiKey.isEmpty else { return }
        if let nextRetry = stocksNextRetryAfter, Date() < nextRetry { return }
        Task { await self.fetchStocksMetadata() }
    }

    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func refreshNow() {
        startPolling(force: true)
    }

    func isRowSourcePaused(_ endpointID: String) -> Bool {
        guard let until = rowSourcePausedUntil[endpointID] else { return false }
        if time.now >= until {
            rowSourcePausedUntil[endpointID] = nil
            return false
        }
        return true
    }

    func pauseRowSource(_ endpointID: String, error: TornAPIError) {
        rowSourcePausedUntil[endpointID] = time.now.addingTimeInterval(Self.dailyRowLimitPause)
        logger.warning("Paused row source \(endpointID) for \(Int(Self.dailyRowLimitPause))s after daily read limit (code \(error.tornCode ?? 14))")
    }

    @discardableResult
    func reserveRequest(_ endpointID: String) -> Bool {
        guard let endpoint = TornEndpointRegistry.endpoint(id: endpointID),
              pollingCoordinator.canMakeRequest() else {
            logger.warning("Request skipped for \(endpointID): per-minute budget reached")
            return false
        }
        pollingCoordinator.record(endpoint)
        return true
    }

    func handlePermanentKeyError(_ error: TornAPIError) {
        resetAccountScopedState()
        keyHalted = true
        keyInfo = nil
        keyValidation = .failure(error.userMessage)
        errorMsg = error.userMessage
        stopPolling()
        logger.error("Polling halted on permanent key/permission error (code \(error.tornCode ?? -1))")
    }

    func validateKey(_ keyOverride: String? = nil) async {
        let trimmed = (keyOverride ?? apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let validationIdentity = accountSession.identity
        guard !trimmed.isEmpty else {
            keyValidation = .failure("Enter your Torn API key first.")
            return
        }
        guard connectivity.isConnected else {
            keyValidation = .failure(TornAPIError.offline.userMessage)
            return
        }
        guard let url = TornAPI.keyInfoURL(for: trimmed) else {
            keyValidation = .failure("Could not build the key-info request.")
            return
        }

        keyValidation = .validating
        guard reserveRequest("key.info") else {
            keyValidation = .failure("Request limit reached. Please try again shortly.")
            return
        }
        let startTime = Date()
        logger.info("Validating key via key-info: \(tornRedactedURL(url))")

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let (data, response) = try await session.data(for: request)
            guard accountSession.isCurrent(validationIdentity) else { return }

            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let apiError = tornAPIError(in: json) {
                recordHealth(
                    "key.info",
                    outcome: .error,
                    since: startTime,
                    bytes: data.count,
                    errorClass: apiError.classification.rawValue
                )
                keyValidation = .failure(apiError.userMessage)
                return
            }

            guard http.statusCode == 200 else {
                recordHealth(
                    "key.info",
                    outcome: .error,
                    since: startTime,
                    bytes: data.count,
                    errorClass: "temporaryBackend"
                )
                keyValidation = .failure("Torn returned HTTP \(http.statusCode). Please try again.")
                return
            }

            let decoded = try JSONDecoder().decode(TornKeyInfo.Response.self, from: data)
            self.keyInfo = decoded.info
            self.keyValidation = .success(KeyValidator.validate(decoded.info))
            recordHealth("key.info", outcome: .ok, since: startTime, bytes: data.count)
            logger.info("Key validated: access level \(decoded.info.access.level)")
        } catch {
            if Task.isCancelled {
                recordHealth("key.info", outcome: .cancelled, since: startTime, bytes: 0)
                return
            }
            guard accountSession.isCurrent(validationIdentity) else { return }
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            let message = mapped?.userMessage
                ?? "Couldn't read Torn's response. Please try again."
            keyValidation = .failure(message)
            recordHealth(
                "key.info",
                outcome: mapped?.classification == .offline ? .offline : .error,
                since: startTime,
                bytes: 0,
                errorClass: mapped?.classification.rawValue ?? "malformedResponse"
            )
            logger.error("Key validation failed: \(String(describing: type(of: error)))")
        }
    }

    func recordHealth(
        _ endpointID: String,
        outcome: EndpointOutcome,
        since start: Date,
        bytes: Int,
        errorClass: String? = nil
    ) {
        endpointHealth.record(
            endpointID: endpointID,
            outcome: outcome,
            latencyMs: Int(Date().timeIntervalSince(start) * 1000),
            responseBytes: bytes,
            errorClass: errorClass
        )
    }

    // MARK: - Fetch Data

    func fetchData() {
        guard connectivity.isConnected else {
            if errorMsg != "No internet connection" {
                errorMsg = "No internet connection"
                logger.warning("Fetch aborted: No internet connection")
            }
            return
        }

        let requestedKey = apiKey
        guard !requestedKey.isEmpty else {
            errorMsg = "API Key required"
            logger.warning("Fetch aborted: API Key required")
            return
        }

        guard let url = TornAPI.url(for: requestedKey) else {
            errorMsg = "Invalid URL"
            logger.error("Fetch aborted: Invalid URL")
            return
        }

        guard reserveRequest("user.fast") else { return }

        isLoading = true
        errorMsg = nil
        let generation = accountSession.identity.generation

        logger.info("Starting data fetch from: \(tornRedactedURL(url))")

        accountSession.startTask(.userSnapshot) {
            let startTime = Date()

            defer {
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed < 0.5 {
                        try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
                    }
                    if self.isCurrentAccount(requestedKey, generation: generation) {
                        self.isLoading = false
                    }
                }
            }

            do {
                let response = try await self.userSnapshotService.load(url)
                let data = response.data
                guard self.isCurrentAccount(requestedKey, generation: generation) else {
                    self.recordHealth("user.fast", outcome: .cancelled, since: startTime, bytes: 0)
                    return
                }

                self.logger.info("HTTP response: \(response.statusCode)")

                switch response.statusCode {
                case 200:
                    if let topLevel = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let apiError = tornAPIError(in: topLevel) {
                            self.recordHealth(
                                "user.fast",
                                outcome: .error,
                                since: startTime,
                                bytes: data.count,
                                errorClass: apiError.classification.rawValue
                            )
                            if apiError.haltsAllRequests {
                                self.handlePermanentKeyError(apiError)
                            } else {
                                self.errorMsg = apiError.userMessage
                                self.logger.warning("User API error class: \(apiError.classification.rawValue)")
                            }
                            return
                        }
                        let keys = topLevel.keys.sorted().joined(separator: ",")
                        self.logger.debug("API response: \(data.count) bytes, keys=[\(keys)]")
                    } else {
                        self.logger.debug("API response: \(data.count) bytes (non-JSON or unparseable)")
                    }

                    async let factionResult: Void = self.fetchFactionData(apiKey: requestedKey, generation: generation)
                    async let userV2Result: Void = self.fetchUserV2Data(apiKey: requestedKey, generation: generation)
                    async let factionV2Result: Void = self.fetchFactionV2Data(apiKey: requestedKey, generation: generation)
                    async let activityResult: Void = self.fetchActivityData(apiKey: requestedKey, generation: generation)
                    let parsed = await self.parseDataInBackground(
                        data: data,
                        apiKey: requestedKey,
                        generation: generation
                    )
                    await factionResult
                    await userV2Result
                    await factionV2Result
                    await activityResult

                    guard self.isCurrentAccount(requestedKey, generation: generation) else { return }
                    if parsed {
                        self.logger.info("Data fetch completed successfully")
                        self.recordHealth("user.fast", outcome: .ok, since: startTime, bytes: data.count)
                    } else {
                        self.recordHealth(
                            "user.fast",
                            outcome: .error,
                            since: startTime,
                            bytes: data.count,
                            errorClass: "malformedResponse"
                        )
                    }

                // NOTE: 403/404 is deliberately NOT treated as a bad key. Torn reports a
                // rejected key as HTTP 200 with an `error` envelope, which is classified
                // above by `handlePermanentKeyError`. A transport-level 403/404 comes from
                // the edge/CDN, so it is transient — telling the user "Invalid API Key"
                // sent them off to regenerate a perfectly good key, and wiping `data`
                // blanked every panel until the next poll (audit finding C-02).
                default:
                    await MainActor.run {
                        guard self.isCurrentAccount(requestedKey, generation: generation) else { return }
                        self.errorMsg = "HTTP Error: \(response.statusCode)"
                    }
                    self.logger.error("HTTP Error: \(response.statusCode)")
                    self.recordHealth(
                        "user.fast",
                        outcome: .error,
                        since: startTime,
                        bytes: data.count,
                        errorClass: "temporaryBackend"
                    )
                }
            } catch {
                if Task.isCancelled {
                    self.recordHealth("user.fast", outcome: .cancelled, since: startTime, bytes: 0)
                    return
                }
                let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
                await MainActor.run {
                    guard self.isCurrentAccount(requestedKey, generation: generation) else { return }
                    self.errorMsg = mapped?.userMessage ?? "Network request failed. Please try again."
                }
                self.logger.error("Network error: \(String(describing: type(of: error)))")
                self.recordHealth(
                    "user.fast",
                    outcome: mapped?.classification == .offline ? .offline : .error,
                    since: startTime,
                    bytes: 0,
                    errorClass: mapped?.classification.rawValue ?? "transport"
                )
            }
        }
    }

    private func parseDataInBackground(data: Data, apiKey: String, generation: UInt) async -> Bool {
        let requestedSelections =
            TornEndpointRegistry.endpoint(id: "user.fast")?.selections ?? []
        let grantedSelections = keyInfo?.selections.user
        let result = await userSnapshotService.parseSnapshot(
            data: data,
            requestedSelections: requestedSelections,
            grantedSelections: grantedSelections
        )

        guard isCurrentAccount(apiKey, generation: generation) else { return false }
        let payload: UserSnapshotPayload
        switch result {
        case .success(let value, _):
            payload = value
        case .apiError(let apiError, _):
            errorMsg = apiError.userMessage
            return false
        case .malformed:
            errorMsg = "Failed to decode user data"
            logger.error("Data error: Failed to decode user data")
            return false
        }

        let decoded = payload.snapshot
        logger.info("Parsed authenticated user data successfully")

        checkNotifications(newData: decoded)
        self.data = decoded

        if let cooldowns = decoded.cooldowns {
            let anchor = decoded.anchorTimestamp ?? Int(Date().timeIntervalSince1970)
            let fresh = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)
            cooldownEnds = cooldownEnds?.merged(with: fresh) ?? fresh
        } else {
            cooldownEnds = nil
        }

        previousBars = decoded.bars
        previousCooldowns = decoded.cooldowns
        previousTravel = decoded.travel
        previousStatus = decoded.status

        moneyData = payload.money
        battleStats = payload.battleStats
        if let attacks = payload.recentAttacks { recentAttacks = attacks }
        if let properties = payload.properties { propertiesData = properties }
        stocksData = payload.stocks

        lastUpdated = Date()
        lastFetchTime = Date()
        errorMsg = nil

        manageLiveTimer()
        checkFeedbackPrompt()

        logger.info("Data updated, lastUpdated: \(self.lastUpdated?.description ?? "nil")")
        return true
    }

    // MARK: - Fetch Row-Based Activity Data

    private func fetchActivityData(apiKey: String, generation: UInt) async {
        guard !apiKey.isEmpty, let url = TornAPI.activityURL(for: apiKey) else { return }
        guard !isRowSourcePaused("user.activity") else { return }

        if let last = lastActivityFetch,
           Date().timeIntervalSince(last) < Self.activityMinInterval {
            return
        }
        guard reserveRequest("user.activity") else { return }
        lastActivityFetch = Date()
        let startTime = Date()

        do {
            let result = try await userSnapshotService.loadActivity(url)
            guard isCurrentAccount(apiKey, generation: generation) else { return }

            switch result {
            case .success(let payload, let responseBytes):
                if let events = payload.events { activityEvents = events }
                if let unread = payload.unreadMessages { unreadMessages = unread }
                if let attacks = payload.recentAttacks { recentAttacks = attacks }
                recordHealth("user.activity", outcome: .ok, since: startTime, bytes: responseBytes)

            case .apiError(let apiError, let responseBytes):
                if apiError.haltsCategoryOnly {
                    pauseRowSource("user.activity", error: apiError)
                }
                recordHealth(
                    "user.activity",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: apiError.classification.rawValue
                )
                logger.warning("Activity API error class: \(apiError.classification.rawValue)")

            case .malformed(let responseBytes):
                recordHealth(
                    "user.activity",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: "malformedResponse"
                )
            }
        } catch {
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            recordHealth(
                "user.activity",
                outcome: mapped?.classification == .offline ? .offline : .error,
                since: startTime,
                bytes: 0,
                errorClass: mapped?.classification.rawValue ?? "transport"
            )
            logger.warning("Activity fetch error (optional): \(String(describing: type(of: error)))")
        }
    }

    // MARK: - Fetch API v2 User Data

    private func fetchUserV2Data(apiKey: String, generation: UInt) async {
        guard !apiKey.isEmpty, let url = TornAPI.userV2URL(for: apiKey),
              reserveRequest("user.v2") else { return }
        let startTime = Date()

        do {
            let result = try await userSnapshotService.loadUserV2(url)
            guard isCurrentAccount(apiKey, generation: generation) else { return }

            switch result {
            case .success(let payload, let responseBytes):
                organizedCrime = payload.organizedCrime
                if let refills = payload.refills { self.refills = refills }
                if let education = payload.education { self.education = education }
                bountiesOnMe = payload.bounties

                if shouldNotifyOCReady(payload.organizedCrime),
                   let organizedCrime = payload.organizedCrime {
                    NotificationManager.shared.send(
                        title: "OC Ready! 💼",
                        body: "\(organizedCrime.name) is ready to execute",
                        type: .ocReady
                    )
                }

                notifyBountiesOnMe()
                logger.info("User v2 data fetched")
                recordHealth("user.v2", outcome: .ok, since: startTime, bytes: responseBytes)

            case .apiError(let apiError, let responseBytes):
                recordHealth(
                    "user.v2",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: apiError.classification.rawValue
                )
                logger.warning("User v2 API error class: \(apiError.classification.rawValue)")

            case .malformed(let responseBytes):
                recordHealth(
                    "user.v2",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: "malformedResponse"
                )
            }
        } catch {
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            recordHealth(
                "user.v2",
                outcome: mapped?.classification == .offline ? .offline : .error,
                since: startTime,
                bytes: 0,
                errorClass: mapped?.classification.rawValue ?? "transport"
            )
            logger.warning("User v2 fetch error (optional): \(String(describing: type(of: error)))")
        }
    }

    func shouldNotifyOCReady(_ oc: OrganizedCrime2?) -> Bool {
        guard let oc, oc.isReady else { return false }
        return notificationCoordinator.shouldFireOnce("oc.ready", epoch: "\(oc.id)")
    }

    private func notifyBountiesOnMe() {
        let currentKeys = Set(bountiesOnMe.map(\.id))
        for bounty in bountiesOnMe where !notifiedBountyKeys.contains(bounty.id) {
            let amount = Self.decimalFormatter.string(from: NSNumber(value: bounty.reward)) ?? "\(bounty.reward)"
            let who: String
            if bounty.isAnonymous == true {
                who = " (anonymous)"
            } else if let name = bounty.listerName {
                who = " from \(name)"
            } else {
                who = ""
            }
            NotificationManager.shared.send(
                title: "⚠️ Bounty on you",
                body: "$\(amount)\(who)",
                type: .bountyOnMe
            )
        }
        notifiedBountyKeys = currentKeys
    }
}
