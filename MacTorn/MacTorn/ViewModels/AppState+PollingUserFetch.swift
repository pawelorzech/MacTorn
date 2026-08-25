import Foundation
import Combine

extension AppState {
    private static var activityMinInterval: TimeInterval { 300 }
    /// Floor between virus reads when the app does not already know a finish time.
    static var virusMinInterval: TimeInterval { 1_800 }

    // MARK: - Polling

    func startPolling() {
        guard !keyHalted else {
            logger.warning("startPolling skipped: polling halted on a permanent key error")
            return
        }
        if timerCancellable != nil,
           time.now.timeIntervalSince(lastFetchTime) < Double(refreshInterval) / 2 {
            return
        }
        timerCancellable?.cancel()
        refreshKeyInfoIfNeeded()
        fetchData()
        triggerStocksMetadataFetchIfNeeded()
        installPollingTimer()
    }

    private func installPollingTimer() {
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
        // Issue #56: an in-flight GitHub update-check must not outlive polling teardown.
        updateCheckTask?.cancel()
    }

    func refreshNow() {
        guard !keyHalted else {
            logger.warning("refreshNow skipped: polling halted on a permanent key error")
            return
        }

        let identity = accountSession.identity
        if lastManualRefreshGeneration == identity.generation,
           let lastManualRefreshAt {
            let elapsed = time.now.timeIntervalSince(lastManualRefreshAt)
            if elapsed >= 0, elapsed < Self.manualRefreshMinInterval {
                return
            }
        }

        // `fetchData` performs connectivity/key/budget validation synchronously. Only
        // accepted requests consume the debounce, so an offline attempt cannot delay
        // the immediate refresh triggered when connectivity returns.
        guard fetchData() else { return }
        lastManualRefreshAt = time.now
        lastManualRefreshGeneration = identity.generation
        if timerCancellable == nil {
            installPollingTimer()
        }
    }

    func isRowSourcePaused(_ endpointID: String) -> Bool {
        endpointGate.isPaused(endpointID)
    }

    /// Records a failure against the endpoint that produced it, so the gate can hold that
    /// one endpoint back for as long as the failure class warrants — a daily row limit for
    /// an hour, a key cooldown for ten minutes, an IP block for an hour — while every
    /// other endpoint keeps polling.
    func noteEndpointFailure(_ error: TornAPIError, for endpointID: String) {
        endpointGate.note(error, for: endpointID)
        if let pause = error.pauseDuration {
            logger.warning(
                "Paused \(endpointID) for \(Int(pause))s after \(error.classification.rawValue) (code \(error.tornCode ?? -1))"
            )
        }
    }

    func pauseRowSource(_ endpointID: String, error: TornAPIError) {
        noteEndpointFailure(error, for: endpointID)
    }

    /// Builds the URL for a registered endpoint, narrowed to the selections this key is
    /// actually allowed to read.
    ///
    /// This is the single builder the registry header has always pointed at (ISA backlog
    /// A-02). Going through the registry rather than the hand-written `TornAPI` helpers is
    /// what makes selection narrowing possible at all: the registry knows which
    /// `/key/info` category an endpoint belongs to, so it can intersect the endpoint's
    /// selections with the ones the key was granted.
    func endpointURL(_ endpointID: String, parameter: Int? = nil, key: String? = nil) -> URL? {
        guard let endpoint = TornEndpointRegistry.endpoint(id: endpointID) else { return nil }
        let resolvedKey = key ?? apiKey
        guard !resolvedKey.isEmpty else { return nil }
        let granted = keyInfo.map { Set($0.selections.names(for: KeyValidator.category(for: endpoint))) }
        return endpoint.url(key: resolvedKey, parameter: parameter, granted: granted)
    }

    /// The single choke point every request-issuing path goes through. Returns false —
    /// and spends nothing — when the gate already knows the call cannot produce data.
    @discardableResult
    func reserveRequest(_ endpointID: String) -> Bool {
        guard let endpoint = TornEndpointRegistry.endpoint(id: endpointID) else {
            logger.error("Request skipped for \(endpointID): not in the endpoint registry")
            return false
        }
        if let denial = endpointGate.denial(for: endpointID,
                                            keyInfo: keyInfo,
                                            coordinator: pollingCoordinator) {
            // Deliberately debug, not warning: a skip is the gate working. Only genuine
            // failures deserve the warning level, or a factionless player's log fills
            // with "faction/basic denied" every thirty seconds.
            logger.debug("Request skipped for \(endpointID): \(denial.label)")
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

    /// Handles the key errors that clear on their own — federal jail, a key-change
    /// cooldown, a key Torn disabled temporarily, an IP block.
    ///
    /// These used to be classified as permanent, which meant a stint in federal jail
    /// stopped MacTorn dead and told the user their key was invalid. Nothing was wrong
    /// with the key: it starts working again by itself. So polling stands down for the
    /// error's `pauseDuration`, says so in plain words, and comes back without the user
    /// touching anything.
    func handleRecoverableKeyError(_ error: TornAPIError) {
        let pause = error.pauseDuration ?? 600
        errorMsg = error.userMessage
        stopPolling()
        logger.warning(
            "Polling paused \(Int(pause))s on recoverable key error (code \(error.tornCode ?? -1))"
        )
        keyResumeTask?.cancel()
        keyResumeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.keyHalted, !self.apiKey.isEmpty else { return }
                self.logger.info("Resuming polling after recoverable key error cool-off")
                self.startPolling()
            }
        }
    }

    /// Loads `/key/info` in the background so the endpoint gate knows what this key can
    /// actually read, without touching `keyValidation` — that state belongs to the
    /// Settings "Test Connection" button and a panel appearing on its own would be a
    /// result the user never asked for.
    ///
    /// Without this, `keyInfo` stayed nil for anyone who never pressed that button, and
    /// the gate had nothing to gate on: the app went right on asking a factionless
    /// player's key for faction data every thirty seconds.
    func refreshKeyInfoIfNeeded() {
        guard keyInfo == nil, !apiKey.isEmpty, !keyHalted, connectivity.isConnected else { return }
        guard keyInfoTask == nil else { return }
        let requestedKey = apiKey
        let identity = accountSession.identity
        guard let url = endpointURL("key.info", key: requestedKey),
              reserveRequest("key.info") else { return }

        keyInfoTask = Task { [weak self] in
            defer { Task { @MainActor in self?.keyInfoTask = nil } }
            guard let self else { return }
            let startTime = Date()
            do {
                let (data, response) = try await self.session.data(for: TornAPIClient.request(for: url))
                guard self.accountSession.isCurrent(identity) else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(TornKeyInfo.Response.self, from: data)
                else {
                    self.recordHealth("key.info", outcome: .error, since: startTime,
                                      bytes: data.count, errorClass: "malformedResponse")
                    return
                }
                self.keyInfo = decoded.info
                self.recordHealth("key.info", outcome: .ok, since: startTime, bytes: data.count)
                self.logger.info("Key capabilities loaded: access level \(decoded.info.access.level)")
            } catch {
                self.recordHealth("key.info", outcome: .error, since: startTime, bytes: 0,
                                  errorClass: "transport")
            }
        }
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
        guard let url = endpointURL("key.info", key: trimmed) else {
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
            let request = TornAPIClient.request(for: url)
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

    @discardableResult
    func fetchData() -> Bool {
        guard connectivity.isConnected else {
            if errorMsg != "No internet connection" {
                errorMsg = "No internet connection"
                logger.warning("Fetch aborted: No internet connection")
            }
            return false
        }

        let requestedKey = apiKey
        guard !requestedKey.isEmpty else {
            errorMsg = "API Key required"
            logger.warning("Fetch aborted: API Key required")
            return false
        }

        guard let url = endpointURL("user.fast", key: requestedKey) else {
            errorMsg = "Invalid URL"
            logger.error("Fetch aborted: Invalid URL")
            return false
        }

        guard reserveRequest("user.fast") else { return false }

        pollSequence &+= 1
        let myPollSequence = pollSequence
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
                    if self.isCurrentAccount(requestedKey, generation: generation),
                       self.pollSequence == myPollSequence {
                        self.isLoading = false
                    }
                }
            }

            do {
                let response = try await self.userSnapshotService.load(url)
                // Issue #46: stamp the receipt the instant the transport hands the bytes
                // back. The Mac↔Torn offset is `server_time - Int(receivedAt)`, so every
                // millisecond spent after this line — the top-level JSON sniff below, the
                // off-actor decode in `parseSnapshot` — would otherwise be booked as clock
                // skew and shift every countdown in the app by that much.
                let receivedAt = self.time.now
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
                            self.noteEndpointFailure(apiError, for: "user.fast")
                            if apiError.haltsAllRequests {
                                self.handlePermanentKeyError(apiError)
                            } else if apiError.classification == .temporaryKey
                                        || apiError.classification == .ipBlocked {
                                self.handleRecoverableKeyError(apiError)
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
                    async let virusResult: Void = self.fetchVirusIfNeeded(apiKey: requestedKey, generation: generation)
                    let parsed = await self.parseDataInBackground(
                        data: data,
                        receivedAt: receivedAt,
                        apiKey: requestedKey,
                        generation: generation
                    )
                    await factionResult
                    await userV2Result
                    await factionV2Result
                    await activityResult
                    await virusResult

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
                if mapped?.classification == .offline,
                   self.lastManualRefreshGeneration == generation,
                   self.pollSequence == myPollSequence {
                    // NWPath can briefly remain "online" after transport already failed.
                    // Re-open the current account's debounce only when this is still the
                    // latest poll, so stale failures cannot mutate newer refresh state.
                    self.lastManualRefreshAt = nil
                    self.lastManualRefreshGeneration = nil
                }
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
        return true
    }

    /// - Parameter receivedAt: the local instant the transport returned these bytes,
    ///   sampled by the caller *before* this decode (issue #46). It is both the anchor
    ///   for the Mac↔Torn offset and the value stored as `lastFetchTime`.
    private func parseDataInBackground(data: Data,
                                       receivedAt: Date,
                                       apiKey: String,
                                       generation: UInt) async -> Bool {
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

        // Issue #46: re-derive the Mac↔Torn skew from THIS snapshot before anything reads
        // a countdown. Deriving it per snapshot (rather than adjusting a running value) is
        // what keeps it from accumulating across polls or latching when the Mac's clock is
        // corrected mid-session.
        //
        // …but the raw derivation is jittery — whole-second truncation on both sides plus
        // this request's latency — and it is now the `now` behind EVERY countdown, so the
        // wobble is damped against the pinned value exactly as `CooldownEnds.merged` damps
        // `endsAt`. Without that, each poll boundary walks the menu bar backwards by a
        // second or three. `receivedAt` is the transport's receipt instant and is also
        // what lands in `lastFetchTime`, so the anchor and the fetch time never disagree.
        let derivedClock = ServerClock(anchor: decoded.anchorTimestamp, localNow: receivedAt)
        serverClock = serverClock.merged(with: derivedClock)

        checkNotifications(newData: decoded)
        self.data = decoded

        if let cooldowns = decoded.cooldowns {
            // Deliberately the RAW anchor, not `serverClock.serverUnix(receivedAt)`: a
            // cooldown's `endsAt` only has to be self-consistent with the response that
            // produced it, and clamping it through the plausibility guard would silently
            // re-anchor cooldowns from a payload whose timestamp is merely unusual.
            let anchor = decoded.anchorTimestamp ?? Int(receivedAt.timeIntervalSince1970)
            let fresh = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)
            cooldownEnds = cooldownEnds?.merged(with: fresh) ?? fresh
        } else {
            cooldownEnds = nil
        }

        // Bars, cooldowns and status no longer need a previous snapshot: their alert
        // edges are decided by the persistent latches in `notificationCoordinator`
        // (see `checkNotifications`). Travel still compares against the last poll —
        // its alert schedules/cancels local notifications rather than latching.
        previousTravel = decoded.travel

        moneyData = payload.money
        battleStats = payload.battleStats
        if let attacks = payload.recentAttacks { recentAttacks = attacks }
        if let properties = payload.properties { propertiesData = properties }
        stocksData = payload.stocks

        lastUpdated = Date()
        lastFetchTime = receivedAt
        errorMsg = nil

        manageLiveTimer()
        checkFeedbackPrompt()

        logger.info("Data updated, lastUpdated: \(self.lastUpdated?.description ?? "nil")")
        return true
    }

    // MARK: - Fetch Row-Based Activity Data

    private func fetchActivityData(apiKey: String, generation: UInt) async {
        guard !apiKey.isEmpty, let url = endpointURL("user.activity", key: apiKey) else { return }
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
                noteEndpointFailure(apiError, for: "user.activity")
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

    // MARK: - Fetch Virus Programming

    /// Reads `/v2/user/virus`, but only when the answer could have changed.
    ///
    /// Writing a virus takes days, and the response is an absolute finish timestamp rather
    /// than a countdown — so between reads there is nothing to learn. This asks again only
    /// once a known virus has finished, or after half an hour of not knowing, which is why
    /// a feature with its own endpoint costs a handful of requests a day rather than one
    /// per poll.
    func fetchVirusIfNeeded(apiKey: String, generation: UInt) async {
        if let virus, !virus.isReady(at: serverNow) { return }
        if let last = lastVirusFetch,
           time.now.timeIntervalSince(last) < Self.virusMinInterval { return }
        guard let url = endpointURL("user.virus", key: apiKey),
              reserveRequest("user.virus") else { return }

        lastVirusFetch = time.now
        let startTime = Date()
        do {
            let result = try await userSnapshotService.loadVirus(url)
            guard isCurrentAccount(apiKey, generation: generation) else { return }

            switch result {
            case .success(let value, let responseBytes):
                let wasProgramming = virus
                virus = value
                if let wasProgramming, value == nil || value?.itemID != wasProgramming.itemID,
                   notificationCoordinator.shouldFireOnce("virus.ready", epoch: "\(wasProgramming.until)") {
                    NotificationManager.shared.send(
                        title: "Virus ready 💾",
                        body: "\(wasProgramming.name) has finished programming",
                        type: .virusReady
                    )
                }
                recordHealth("user.virus", outcome: .ok, since: startTime, bytes: responseBytes)

            case .apiError(let apiError, let responseBytes):
                noteEndpointFailure(apiError, for: "user.virus")
                recordHealth("user.virus", outcome: .error, since: startTime,
                             bytes: responseBytes, errorClass: apiError.classification.rawValue)

            case .malformed(let responseBytes):
                recordHealth("user.virus", outcome: .error, since: startTime,
                             bytes: responseBytes, errorClass: "malformedResponse")
            }
        } catch {
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            recordHealth("user.virus",
                         outcome: mapped?.classification == .offline ? .offline : .error,
                         since: startTime, bytes: 0,
                         errorClass: mapped?.classification.rawValue ?? "transport")
        }
    }

    // MARK: - Fetch API v2 User Data

    private func fetchUserV2Data(apiKey: String, generation: UInt) async {
        guard !apiKey.isEmpty, let url = endpointURL("user.v2", key: apiKey),
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
                if let counts = payload.notifications {
                    notificationCounts = counts
                    // The unread count used to arrive with the row-based activity call, so
                    // it was up to five minutes stale. It rides the fast poll now.
                    unreadMessages = counts.messages
                }

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
        guard let oc, oc.isReady(at: serverNow) else { return false }
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
