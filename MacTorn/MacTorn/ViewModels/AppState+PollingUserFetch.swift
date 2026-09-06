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
        // Assigning over an AnyCancellable cancels the old one, so a separate cancel here
        // only served to make `timerCancellable != nil` stop meaning "a timer is running" —
        // which `refreshNow` relies on.
        installPollingTimer()
        let needsCapabilities = keyInfo == nil && !apiKey.isEmpty && connectivity.isConnected
        startFirstFetch()
        if !needsCapabilities { triggerReferenceDataFetchIfNeeded() }
    }

    /// Issues the first poll of a session, ordered behind the key-capabilities load.
    ///
    /// The order is the whole point. The key's capabilities have to land BEFORE the first
    /// poll, because that poll is the one selection narrowing exists for: started
    /// alongside it, `fetchData()` ran with `keyInfo` still nil and asked for everything,
    /// and a key that cannot read one of those selections answers with code 16 — which
    /// halts the app before a narrowed retry can happen.
    ///
    /// The ordering is enforced with `awaitingFirstKeyInfo` rather than by delaying the
    /// timer. Withholding the timer until the fetch completed closed this hole and opened
    /// two others: `refreshNow` installs a timer whenever it finds none, so a manual
    /// refresh during the wait produced a second one and left the first orphaned, and a
    /// cancelled first fetch left the app with no timer at all.
    @discardableResult
    private func startFirstFetch() -> Bool {
        guard keyInfo == nil, !apiKey.isEmpty, connectivity.isConnected else {
            return fetchData()
        }
        guard !awaitingFirstKeyInfo else { return false }

        // Reserve `/key/info` on the caller's turn. Besides keeping accounting exact,
        // this preserves `refreshNow`'s synchronous acceptance semantics: debounce and
        // request-budget readers see the accepted refresh before its async transport runs.
        var reservedKeyInfoURL: URL?
        if keyInfoTask == nil {
            guard let url = endpointURL("key.info"), reserveRequest("key.info") else {
                return false
            }
            reservedKeyInfoURL = url
        }

        awaitingFirstKeyInfo = true
        pollSequence &+= 1
        let identity = accountSession.identity
        firstFetchGeneration &+= 1
        let generation = firstFetchGeneration
        firstFetchTask?.cancel()
        firstFetchTask = Task { [weak self] in
            await self?.loadKeyInfoIfNeeded(
                preReservedURL: reservedKeyInfoURL,
                expectedIdentity: identity
            )
            guard let self else { return }
            // A superseded attempt must not clear the window a newer one just opened. This
            // is the `defer`-clobber bug in a second costume: the handle was fixed, the
            // flag was not, and clearing it here unguarded let a stale task unprotect a
            // live load. The newer task owns the flag and will clear it.
            guard self.firstFetchGeneration == generation else { return }
            // Cleared before the cancellation check on purpose: a cancelled first fetch
            // must still unblock the timer, or polling stops for the session.
            self.awaitingFirstKeyInfo = false
            // The wait is unbounded, so re-check what may have changed across it. Without
            // this the task resumes into a halted app, or into an account the user has
            // since switched away from, and spends a request either way.
            guard !Task.isCancelled,
                  self.accountSession.isCurrent(identity),
                  !self.keyHalted else { return }
            self.fetchData(reusingPollSequence: true)
        }
        return true
    }

    private func installPollingTimer() {
        timerCancellable = Timer.publish(every: Double(refreshInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                // A tick during the first key-capabilities load would issue exactly the
                // un-narrowed request that load exists to prevent. `/key/info` slower than
                // one refresh interval is a plain cold handshake at the 15-second setting,
                // not a rare event.
                guard !self.awaitingFirstKeyInfo else { return }
                if self.keyInfo == nil {
                    self.startFirstFetch()
                    return
                }
                self.refreshKeyInfoIfNeeded()
                self.fetchData()
                self.triggerReferenceDataFetchIfNeeded()
            }
    }

    private func triggerStocksMetadataFetchIfNeeded() {
        guard stocksMetadata.isEmpty, !apiKey.isEmpty else { return }
        if let nextRetry = stocksNextRetryAfter, Date() < nextRetry { return }
        Task { await self.fetchStocksMetadata() }
    }

    /// Slow-changing reference data, refreshed alongside the stock names. Both are cheap
    /// no-ops on almost every tick — they only reach the network when their cache is stale.
    private func triggerReferenceDataFetchIfNeeded() {
        triggerStocksMetadataFetchIfNeeded()
        triggerItemCatalogFetchIfNeeded()
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

        // A manual refresh cannot jump or restart the first key-capabilities load. The
        // pending first fetch satisfies this refresh when it lands.
        guard !awaitingFirstKeyInfo else { return }

        // Save & Connect and connectivity restoration both arrive here immediately after
        // account-scoped state cleared `keyInfo`. Route that first refresh through the
        // same ordered handshake as `startPolling`: `/key/info` must finish before the
        // first user request can be narrowed safely.
        if keyInfo == nil, !apiKey.isEmpty, connectivity.isConnected {
            if timerCancellable == nil { installPollingTimer() }
            guard startFirstFetch() else { return }
            lastManualRefreshAt = time.now
            lastManualRefreshGeneration = identity.generation
            return
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

    /// Records a failure with the scope Torn assigns it: endpoint-local for malformed
    /// requests/daily row limits, account-wide for rate/key/network restrictions, and a
    /// capability refresh for code 16. Legacy endpoint wrappers enter here too.
    func noteEndpointFailure(_ error: TornAPIError, for endpointID: String) {
        switch error.classification {
        case .permanentKey, .temporaryKey, .ipBlocked, .rateLimit,
             .insufficientPermissions:
            // Legacy market/forum callers enter through this method. Route their
            // account/capability errors through the same central semantics too.
            handleAPIError(error, for: endpointID)
            return
        default:
            endpointGate.note(error, for: endpointID)
        }
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
        logger.error("Polling halted on permanent key error (code \(error.tornCode ?? -1))")
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
        // These refuse the whole account, not one endpoint. Without this the eight other
        // endpoints keep firing into the same wall for the length of the cool-off — and an
        // IP block is a wall that continued requests make thicker.
        endpointGate.noteAccountWideFailure(error)
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

    /// Applies Torn application errors consistently regardless of which service wrapper
    /// decoded the envelope. In particular, code 5 is per user (and therefore global),
    /// while code 16 is a stale-capability signal rather than an invalid-key signal.
    func handleAPIError(_ error: TornAPIError, for endpointID: String) {
        switch error.classification {
        case .permanentKey:
            handlePermanentKeyError(error)
        case .temporaryKey, .ipBlocked, .rateLimit:
            handleRecoverableKeyError(error)
        case .insufficientPermissions:
            errorMsg = error.userMessage
            guard endpointGate.beginPermissionRetry(for: endpointID) else {
                endpointGate.pause(endpointID, for: 3_600, reason: .insufficientPermissions)
                logger.warning("Code 16 persisted after capability refresh for \(endpointID)")
                return
            }
            keyInfo = nil
            keyInfoLoadedAt = nil
            logger.warning("Refreshing capabilities after code 16 from \(endpointID)")
            // `/key/info` itself cannot be narrowed. Avoid an infinite self-refresh loop
            // if Torn unexpectedly answers code 16 on the capability endpoint.
            if endpointID != "key.info" { startFirstFetch() }
        default:
            noteEndpointFailure(error, for: endpointID)
            errorMsg = error.userMessage
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
        guard keyInfoTask == nil else { return }
        Task { [weak self] in await self?.loadKeyInfoIfNeeded() }
    }

    /// Loads `/key/info` when what MacTorn knows about the key is missing or old.
    ///
    /// Two things this has to get right that the first version did not.
    ///
    /// **It must be awaitable.** `startPolling` needs the answer before the first fetch,
    /// because that fetch is the one selection narrowing exists for.
    ///
    /// **It must expire.** Read once per key and never again, a snapshot taken while the
    /// player had no faction kept the gate refusing faction endpoints for the life of the
    /// process — a player who joined a faction mid-session lost the chain alert until they
    /// relaunched. The reverse cost just as much: one flaky `/key/info` at launch left
    /// `keyInfo` nil forever, so the gate silently did nothing for the whole session and a
    /// factionless player went back to spending a request on faction data every poll.
    func loadKeyInfoIfNeeded(
        preReservedURL: URL? = nil,
        expectedIdentity: AccountIdentity? = nil
    ) async {
        guard !apiKey.isEmpty, !keyHalted, connectivity.isConnected else { return }
        if let expectedIdentity, !accountSession.isCurrent(expectedIdentity) { return }
        // Join an in-flight load rather than returning past it. Returning immediately made
        // the guard that prevents a double-start also defeat the await-before-fetch
        // ordering for every caller that was not first: a second `startPolling` awaited
        // this, got nothing, and fetched with `keyInfo` still nil.
        if let existing = keyInfoTask {
            await existing.value
            return
        }
        if keyInfo != nil, let loadedAt = keyInfoLoadedAt,
           time.now.timeIntervalSince(loadedAt) < Self.keyInfoMaxAge {
            return
        }
        let identity = expectedIdentity ?? accountSession.identity
        let requestedKey = identity.apiKey
        let url: URL
        if let preReservedURL {
            url = preReservedURL
        } else {
            guard let built = endpointURL("key.info", key: requestedKey),
                  reserveRequest("key.info") else { return }
            url = built
        }

        let task = Task { [weak self] in
            guard let self else { return }
            let startTime = Date()
            do {
                let (data, response) = try await self.session.data(for: TornAPIClient.request(for: url))
                guard self.accountSession.isCurrent(identity) else { return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let apiError = tornAPIError(in: json) {
                    self.handleAPIError(apiError, for: "key.info")
                    self.recordHealth("key.info", outcome: .error, since: startTime,
                                      bytes: data.count,
                                      errorClass: apiError.classification.rawValue)
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    self.recordHealth("key.info", outcome: .error, since: startTime,
                                      bytes: data.count, errorClass: "temporaryBackend")
                    return
                }
                guard let decoded = try? JSONDecoder().decode(TornKeyInfo.Response.self, from: data) else {
                    self.recordHealth("key.info", outcome: .error, since: startTime,
                                      bytes: data.count, errorClass: "malformedResponse")
                    return
                }
                self.keyInfo = decoded.info
                self.keyInfoLoadedAt = self.time.now
                self.recordHealth("key.info", outcome: .ok, since: startTime, bytes: data.count)
                self.logger.info("Key capabilities loaded: access level \(decoded.info.access.level)")
            } catch {
                self.recordHealth("key.info", outcome: .error, since: startTime, bytes: 0,
                                  errorClass: "transport")
            }
        }
        keyInfoTask = task
        // Awaited rather than fired and forgotten, so `startPolling` can order the first
        // fetch behind it. The handle is cleared here, on the same actor, instead of from
        // a deferred hop that could outlive an account change and null a newer task's
        // handle.
        await task.value
        if keyInfoTask == task { keyInfoTask = nil }
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
    func fetchData(reusingPollSequence: Bool = false) -> Bool {
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

        if !reusingPollSequence { pollSequence &+= 1 }
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
                            self.handleAPIError(apiError, for: "user.fast")
                            self.logger.warning("User API error class: \(apiError.classification.rawValue)")
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
                        self.endpointGate.noteSuccess(for: "user.fast")
                        self.logger.info("Data fetch completed successfully")
                        self.recordHealth("user.fast", outcome: .ok, since: startTime, bytes: data.count)
                        self.triggerReferenceDataFetchIfNeeded()
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
            handleAPIError(apiError, for: "user.fast")
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
                endpointGate.noteSuccess(for: "user.activity")
                if let events = payload.events { activityEvents = events }
                if let unread = payload.unreadMessages { unreadMessages = unread }
                if let attacks = payload.recentAttacks { recentAttacks = attacks }
                recordHealth("user.activity", outcome: .ok, since: startTime, bytes: responseBytes)

            case .apiError(let apiError, let responseBytes):
                handleAPIError(apiError, for: "user.activity")
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
                endpointGate.noteSuccess(for: "user.virus")
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
                handleAPIError(apiError, for: "user.virus")
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
                endpointGate.noteSuccess(for: "user.v2")
                applyUserV2Payload(payload)
                logger.info("User v2 data fetched")
                recordHealth(
                    "user.v2",
                    outcome: payload.malformedSelections.isEmpty ? .ok : .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: payload.malformedSelections.isEmpty ? nil : "malformedResponse"
                )

            case .apiError(let apiError, let responseBytes):
                handleAPIError(apiError, for: "user.v2")
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

    /// Applies only sections that were decoded successfully. This makes partial v2
    /// responses monotonic: one bad sibling cannot erase the last-good value of another.
    func applyUserV2Payload(_ payload: UserV2Payload) {
        switch payload.organizedCrime {
        case .unchanged:
            break
        case .replace(let value):
            organizedCrime = value
            if shouldNotifyOCReady(value), let value {
                NotificationManager.shared.send(
                    title: "OC Ready! 💼",
                    body: "\(value.name) is ready to execute",
                    type: .ocReady
                )
            }
        }
        if case .replace(let value) = payload.refills { refills = value }
        if case .replace(let value) = payload.education { education = value }
        if case .replace(let value) = payload.bounties {
            bountiesOnMe = value
            notifyBountiesOnMe()
        }
        if case .replace(let counts) = payload.notifications {
            notificationCounts = counts
            // This used to arrive with the row-based activity call, so it was up to five
            // minutes stale. It rides the fast poll now.
            unreadMessages = counts.messages
        }
    }

    func shouldNotifyOCReady(_ oc: OrganizedCrime2?) -> Bool {
        guard let oc, oc.isReady(at: serverNow) else { return false }
        return notificationCoordinator.shouldFireOnce("oc.ready", epoch: "\(oc.id)")
    }

    private func notifyBountiesOnMe() {
        // `shouldFireOnce` both tests and records, so this filter performs the dedup
        // write as well — the same usage as `shouldNotifyOCReady` above. The epoch is
        // the bounty id, which never changes for a given bounty, so a bounty announces
        // itself exactly once and then stays quiet for as long as it hangs there,
        // across relaunches.
        let fresh = bountiesOnMe.filter {
            notificationCoordinator.shouldFireOnce("bounty.\($0.id)", epoch: $0.id)
        }
        guard let banner = Self.bountyBanner(for: fresh) else { return }
        NotificationManager.shared.send(title: banner.title, body: banner.body, type: .bountyOnMe)
    }

    /// The banner for a set of freshly-seen bounties, or `nil` when there is nothing to
    /// say. More than one at once collapses into a single summary rather than a stack of
    /// banners, matching `flushPendingPriceAlerts()`.
    ///
    /// Pure and non-private so the aggregation is testable: `NotificationManager.shared`
    /// is a singleton with no injection seam, so the alternative was shipping this half
    /// unasserted.
    static func bountyBanner(for fresh: [Bounty]) -> (title: String, body: String)? {
        guard !fresh.isEmpty else { return nil }

        if fresh.count == 1 {
            let bounty = fresh[0]
            return ("⚠️ Bounty on you", "$\(bountyAmount(bounty))\(bountyLister(bounty))")
        }

        return ("⚠️ \(fresh.count) bounties on you", "$\(bountyTotalAmount(fresh)) total")
    }

    static func bountyTotalAmount(_ bounties: [Bounty]) -> String {
        let total = bounties.reduce(Decimal.zero) { $0 + Decimal($1.reward) }
        return decimalFormatter.string(from: NSDecimalNumber(decimal: total)) ?? "\(total)"
    }

    private static func bountyAmount(_ bounty: Bounty) -> String {
        decimalFormatter.string(from: NSNumber(value: bounty.reward)) ?? "\(bounty.reward)"
    }

    private static func bountyLister(_ bounty: Bounty) -> String {
        if bounty.isAnonymous == true { return " (anonymous)" }
        if let name = bounty.listerName { return " from \(name)" }
        return ""
    }
}
