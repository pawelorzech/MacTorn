import Foundation
import Combine

extension AppState {
    // MARK: - Polling

    func startPolling() {
        guard !keyHalted else {
            logger.warning("startPolling skipped: polling halted on a permanent key error")
            return
        }
        if pollTimer.isRunning,
           time.now.timeIntervalSince(player.lastFetchTime) < Double(refreshInterval) / 2 {
            return
        }
        installPollingTimer()
        let needsCapabilities = requester.keyInfo == nil && !apiKey.isEmpty && connectivity.isConnected
        startFirstFetch()
        if !needsCapabilities { triggerReferenceDataFetchIfNeeded() }
    }

    /// Issues the first poll of a session, ordered behind the key-capabilities load.
    ///
    /// The first poll is the one selection narrowing exists for: sent with capabilities
    /// unknown it asks for everything, and a key that cannot read one selection answers
    /// with code 16 for the whole request. So `/key/info` lands first.
    ///
    /// The ordering is held by `awaitingFirstKeyInfo` rather than by withholding the
    /// timer: `refreshNow` installs a timer whenever it finds none, so a manual refresh
    /// during the wait would orphan a second one, and a cancelled first fetch would leave
    /// no timer at all.
    @discardableResult
    func startFirstFetch() -> Bool {
        guard requester.keyInfo == nil, !apiKey.isEmpty, connectivity.isConnected else {
            return fetchData()
        }
        guard !awaitingFirstKeyInfo else { return false }

        // Charge `/key/info` on the caller's turn, so debounce and budget readers see the
        // accepted refresh before its transport runs.
        var reservedKeyInfo: TornPreparedRequest?
        if keyInfoTask == nil {
            guard let request = requester.prepare("key.info") else { return false }
            reservedKeyInfo = request
        }

        awaitingFirstKeyInfo = true
        pollSequence &+= 1
        let identity = accountSession.identity
        firstFetchGeneration &+= 1
        let generation = firstFetchGeneration
        firstFetchTask?.cancel()
        firstFetchTask = Task { [weak self] in
            await self?.loadKeyInfoIfNeeded(prepared: reservedKeyInfo, expectedIdentity: identity)
            guard let self else { return }
            // A superseded attempt must not clear the window a newer one just opened.
            guard self.firstFetchGeneration == generation else { return }
            // Cleared before the cancellation check: a cancelled first fetch must still
            // unblock the timer, or polling stops for the session.
            self.awaitingFirstKeyInfo = false
            guard !Task.isCancelled,
                  self.accountSession.isCurrent(identity),
                  !self.keyHalted else { return }
            self.fetchData(reusingPollSequence: true)
        }
        return true
    }

    func installPollingTimer() {
        pollTimer.start(every: Double(refreshInterval)) { [weak self] in
                guard let self else { return }
                // A tick during the first key-capabilities load would send exactly the
                // un-narrowed request that load exists to prevent.
                guard !self.awaitingFirstKeyInfo else { return }
                if self.requester.keyInfo == nil {
                    self.startFirstFetch()
                    return
                }
                self.refreshKeyInfoIfNeeded()
                self.fetchData()
                self.triggerReferenceDataFetchIfNeeded()
            }
        // Every path that starts polling comes through here, so the price-alert timer is
        // started alongside in one place.
        syncPriceAlertPolling()
    }

    private func triggerReferenceDataFetchIfNeeded() {
        triggerStocksMetadataFetchIfNeeded()
        triggerItemCatalogFetchIfNeeded()
    }

    func stopPolling() {
        pollTimer.stop()
        stopPriceAlertPolling()
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

        // The pending first fetch satisfies this refresh when it lands.
        guard !awaitingFirstKeyInfo else { return }

        // Save & Connect and connectivity restoration arrive here right after account
        // state cleared the capabilities, so they take the same ordered handshake.
        if requester.keyInfo == nil, !apiKey.isEmpty, connectivity.isConnected {
            if !pollTimer.isRunning { installPollingTimer() }
            guard startFirstFetch() else { return }
            lastManualRefreshAt = time.now
            lastManualRefreshGeneration = identity.generation
            return
        }

        // Only accepted requests consume the debounce, so an offline attempt cannot delay
        // the refresh triggered when connectivity returns.
        guard fetchData() else { return }
        lastManualRefreshAt = time.now
        lastManualRefreshGeneration = identity.generation
        if !pollTimer.isRunning {
            installPollingTimer()
        }
    }

    // MARK: - Account-wide errors

    /// Errors that say something about the key or the network rather than one endpoint.
    /// The requester sends every such error here, whichever endpoint met it.
    func handleAccountError(_ error: TornAPIError, for endpointID: String) {
        switch error.classification {
        case .permanentKey:
            handlePermanentKeyError(error)
        case .insufficientPermissions:
            errorMsg = error.userMessage
            guard requester.gate.beginPermissionRetry(for: endpointID) else {
                requester.gate.pause(endpointID, for: 3_600, reason: .insufficientPermissions)
                logger.warning("Code 16 persisted after capability refresh for \(endpointID)")
                return
            }
            requester.forgetKeyInfo()
            logger.warning("Refreshing capabilities after code 16 from \(endpointID)")
            // `/key/info` itself cannot be narrowed; never refresh it in a loop.
            if endpointID != "key.info" { startFirstFetch() }
        default:
            handleRecoverableKeyError(error)
        }
    }

    func handlePermanentKeyError(_ error: TornAPIError) {
        resetAccountScopedState()
        keyHalted = true
        keyValidation = .failure(error.userMessage)
        errorMsg = error.userMessage
        stopPolling()
        // Forum Watch runs on its own timer and would keep spending the rejected key.
        stopForumPolling()
        logger.error("Polling halted on permanent key error (code \(error.tornCode ?? -1))")
    }

    /// Federal jail, a key-change cooldown, a temporarily disabled key, an IP block: the
    /// key starts working again by itself, so polling stands down for the error's
    /// `pauseDuration` and resumes without the user touching anything.
    func handleRecoverableKeyError(_ error: TornAPIError) {
        let pause = error.pauseDuration ?? 600
        // These refuse the whole account; an IP block is a wall continued requests thicken.
        requester.gate.noteAccountWideFailure(error)
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

    // MARK: - Key capabilities

    nonisolated static func decodeKeyInfo(_ data: Data, _ json: [String: Any]) -> TornKeyInfo? {
        (try? JSONDecoder().decode(TornKeyInfo.Response.self, from: data))?.info
    }

    /// Re-reads `/key/info` when the cached answer is missing or older than an hour —
    /// the gate refuses requests on the strength of it, so a stale one keeps a working
    /// endpoint switched off. Runs on every timer tick, so the fresh case returns before
    /// allocating a task.
    func refreshKeyInfoIfNeeded() {
        guard keyInfoTask == nil, !keyInfoIsFresh else { return }
        Task { [weak self] in await self?.loadKeyInfoIfNeeded() }
    }

    private var keyInfoIsFresh: Bool {
        guard requester.keyInfo != nil, let loadedAt = requester.keyInfoLoadedAt else { return false }
        return time.now.timeIntervalSince(loadedAt) < Self.keyInfoMaxAge
    }

    /// Awaitable, so the first fetch can wait for it. A caller arriving while a load is in
    /// flight joins it instead of returning past it.
    func loadKeyInfoIfNeeded(prepared: TornPreparedRequest? = nil,
                             expectedIdentity: AccountIdentity? = nil) async {
        guard canTalkToTorn else { return }
        if let expectedIdentity, !accountSession.isCurrent(expectedIdentity) { return }
        if let existing = keyInfoTask {
            await existing.value
            return
        }
        guard !keyInfoIsFresh, let request = prepared ?? requester.prepare("key.info") else { return }

        let task = Task { [weak self] in
            guard let self,
                  let info = await self.requester.send(request, decode: Self.decodeKeyInfo).value else { return }
            self.requester.adopt(info, at: self.time.now)
            self.logger.info("Key capabilities loaded: access level \(info.access.level)")
        }
        keyInfoTask = task
        await task.value
        if keyInfoTask == task { keyInfoTask = nil }
    }

    /// Settings' "Test Connection". Validates whatever key is typed, saved or not; only a
    /// result for the saved key updates the capabilities the gate uses.
    func validateKey(_ keyOverride: String? = nil) async {
        keyValidationGeneration &+= 1
        let validationGeneration = keyValidationGeneration
        let trimmed = (keyOverride ?? apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = accountSession.identity
        guard !trimmed.isEmpty else {
            keyValidation = .failure("Enter your Torn API key first.")
            return
        }
        guard connectivity.isConnected else {
            keyValidation = .failure(TornAPIError.offline.userMessage)
            return
        }
        guard requester.url("key.info", key: trimmed) != nil else {
            keyValidation = .failure("Could not build the key-info request.")
            return
        }
        keyValidation = .validating
        guard let request = requester.prepare("key.info", key: trimmed) else {
            keyValidation = .failure(requester.denial("key.info")?.userExplanation
                ?? "Request limit reached. Please try again shortly.")
            return
        }
        logger.info("Validating key via key-info: \(tornRedactedURL(request.url))")

        let result = await requester.send(request, decode: Self.decodeKeyInfo)
        guard keyValidationGeneration == validationGeneration,
              accountSession.isCurrent(identity) else { return }
        switch result {
        case .loaded(let info):
            if trimmed == apiKey.trimmingCharacters(in: .whitespacesAndNewlines) {
                requester.adopt(info, at: time.now)
            }
            keyValidation = .success(KeyValidator.validate(info))
            logger.info("Key validated: access level \(info.access.level)")
        case .failed(.api(let error)):
            keyValidation = .failure(error.userMessage)
        case .failed(.http(let status)):
            keyValidation = .failure("Torn returned HTTP \(status). Please try again.")
        case .failed(.transport(let error?)):
            keyValidation = .failure(error.userMessage)
        case .superseded:
            keyValidation = .idle
        case .failed, .nothingToServe, .skipped:
            keyValidation = .failure("Couldn't read Torn's response. Please try again.")
        }
    }

    // MARK: - User snapshot

    @discardableResult
    func fetchData(reusingPollSequence: Bool = false) -> Bool {
        guard connectivity.isConnected else {
            if errorMsg != "No internet connection" {
                errorMsg = "No internet connection"
                logger.warning("Fetch aborted: No internet connection")
            }
            return false
        }

        companion.start(app: self)
        guard !apiKey.isEmpty else {
            errorMsg = "API Key required"
            logger.warning("Fetch aborted: API Key required")
            return false
        }
        guard requester.url("user.fast") != nil else {
            errorMsg = "MacTorn couldn't build the Torn request. Please report this."
            logger.error("Fetch aborted: Invalid URL")
            return false
        }
        guard let request = requester.prepare("user.fast") else { return false }

        if !reusingPollSequence { pollSequence &+= 1 }
        let myPollSequence = pollSequence
        isLoading = true
        errorMsg = nil
        let identity = request.identity
        logger.info("Starting data fetch from: \(tornRedactedURL(request.url))")

        accountSession.startTask(.userSnapshot) {
            let startTime = Date()
            defer {
                // The spinner stays up at least half a second, so a fast poll reads as a
                // refresh rather than a flicker.
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startTime)
                    if elapsed < 0.5 {
                        try? await Task.sleep(nanoseconds: UInt64((0.5 - elapsed) * 1_000_000_000))
                    }
                    if self.accountSession.isCurrent(identity), self.pollSequence == myPollSequence {
                        self.isLoading = false
                    }
                }
            }

            // The Mac↔Torn offset is `server_time - receivedAt`, so receipt is stamped the instant the
            // transport returns, before the off-actor decode; decode time would otherwise be booked as clock skew.
            var receivedAt = self.time.now
            let requested = TornEndpointRegistry.endpoint(id: "user.fast")?.selections ?? []
            let granted = self.requester.keyInfo?.selections.user
            let result = await self.requester.send(request) { (url) async throws -> TornServiceResult<UserSnapshotPayload> in
                let response = try await self.userSnapshotService.load(url)
                receivedAt = self.time.now
                guard response.statusCode == 200 else {
                    return .httpError(statusCode: response.statusCode, responseBytes: response.data.count)
                }
                return await self.userSnapshotService.parseSnapshot(
                    data: response.data, requestedSelections: requested, grantedSelections: granted
                )
            }

            switch result {
            case .loaded(let payload):
                self.publishSnapshot(payload, receivedAt: receivedAt)
            case .failed(.malformed):
                self.errorMsg = TornAPIError.malformedResponse(detail: "").userMessage
                self.logger.error("Data error: Failed to decode user data")
            case .failed(.api(let error)):
                // Account-wide errors already set the message through `handleAccountError`.
                if !error.isAccountWide { self.errorMsg = error.userMessage }
                return
            case .failed(.http(let status)):
                // Transport 403/404 come from the edge, not the key; the last good
                // snapshot stays on screen.
                self.errorMsg = TornAPIError.httpStatusMessage(status)
                self.logger.error("HTTP Error: \(status)")
                return
            case .failed(.transport(let mapped)):
                if mapped?.classification == .offline,
                   self.lastManualRefreshGeneration == identity.generation,
                   self.pollSequence == myPollSequence {
                    // NWPath can stay "online" briefly after the transport failed. Reopen
                    // the debounce only for the latest poll of this account.
                    self.lastManualRefreshAt = nil
                    self.lastManualRefreshGeneration = nil
                }
                self.errorMsg = mapped?.userMessage ?? "Network request failed. Please try again."
                return
            case .nothingToServe, .skipped, .superseded:
                return
            }

            async let faction: Void = self.fetchFactionData()
            async let userV2: Void = self.fetchUserV2Data()
            async let factionV2: Void = self.fetchFactionV2Data()
            async let activity: Void = self.fetchActivityData()
            async let virusRead: Void = self.fetchVirusIfNeeded()
            _ = await (faction, userV2, factionV2, activity, virusRead)

            guard !Task.isCancelled, self.accountSession.isCurrent(identity) else { return }
            if case .loaded = result { self.triggerReferenceDataFetchIfNeeded() }
        }
        return true
    }

    /// `receivedAt` anchors the Mac↔Torn offset and becomes `lastFetchTime`, so the two
    /// never disagree.
    private func publishSnapshot(_ payload: UserSnapshotPayload, receivedAt: Date) {
        let decoded = payload.snapshot

        // The skew is re-derived from this snapshot (so it cannot accumulate or latch across a Mac clock
        // correction) and damped against the pinned value, as `CooldownEnds.merged` does for `endsAt`: the
        // raw value wobbles by a second or three per poll and would walk every countdown backwards.
        let derivedClock = ServerClock(anchor: decoded.anchorTimestamp, localNow: receivedAt)
        player.serverClock = player.serverClock.merged(with: derivedClock)

        checkNotifications(newData: decoded)
        player.data = decoded

        if let cooldowns = decoded.cooldowns {
            // Deliberately the raw anchor: a cooldown's `endsAt` only has to agree with the
            // response that produced it, and the plausibility clamp would silently
            // re-anchor cooldowns from a payload whose timestamp is merely unusual.
            let anchor = decoded.anchorTimestamp ?? Int(receivedAt.timeIntervalSince1970)
            let fresh = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)
            player.cooldownEnds = player.cooldownEnds?.merged(with: fresh) ?? fresh
        } else {
            player.cooldownEnds = nil
        }

        // Travel's alert schedules and cancels local notifications, so it still compares
        // against the previous poll; everything else latches in `notificationCoordinator`.
        player.previousTravel = decoded.travel

        player.moneyData = payload.money
        player.battleStats = payload.battleStats
        if let attacks = payload.recentAttacks { player.recentAttacks = attacks }
        if let properties = payload.properties { player.propertiesData = properties }
        player.stocksData = payload.stocks

        player.lastUpdated = time.now
        player.lastFetchTime = receivedAt
        errorMsg = nil

        manageLiveTimer()
        publishWidgets()
        checkFeedbackPrompt()
    }

    // MARK: - Slower user sources

    private func fetchActivityData() async {
        guard requester.isDue("user.activity"),
              let payload = await requester.fetch("user.activity", decode: UserSnapshotService.decodeActivity).value
        else { return }
        if let events = payload.events { player.activityEvents = events }
        if let attacks = payload.recentAttacks { player.recentAttacks = attacks }
    }

    /// Writing a virus takes days and Torn answers with an absolute finish time, so the
    /// endpoint is only re-read once a known virus has finished, or after the registry's
    /// half-hour floor when none is known.
    func fetchVirusIfNeeded() async {
        if let virus = player.virus, !virus.isReady(at: serverNow) { return }
        guard requester.isDue("user.virus"),
              case .loaded(let value) = await requester.fetch("user.virus", decode: UserSnapshotService.decodeVirus)
        else { return }
        let wasProgramming = player.virus
        player.virus = value
        publishWidgets()
        if let wasProgramming, value == nil || value?.itemID != wasProgramming.itemID,
           notificationCoordinator.shouldFireOnce(AlertKey.virusReady, epoch: "\(wasProgramming.until)") {
            notifier.send(title: "Virus ready 💾",
                          body: "\(wasProgramming.name) has finished programming",
                          type: .virusReady)
        }
    }

    private func fetchUserV2Data() async {
        guard let endpoint = TornEndpointRegistry.endpoint(id: "user.v2") else { return }
        let requested = Set(endpoint.resolvedSelections(granted: requester.keyInfo?.grantedNames(for: endpoint)))
        guard let payload = await requester.fetch(
            "user.v2", decode: UserSnapshotService.decodeUserV2(requested: requested)
        ).value else { return }
        applyUserV2Payload(payload)
        if !payload.malformedSelections.isEmpty {
            requester.record("user.v2", .error, since: Date(), bytes: 0, errorClass: .malformedResponse)
        }
    }

    /// Applies only sections that decoded, so one bad sibling cannot erase another's
    /// last good value.
    func applyUserV2Payload(_ payload: UserV2Payload) {
        defer { publishWidgets() }
        switch payload.organizedCrime {
        case .unchanged:
            break
        case .replace(let value):
            player.organizedCrime = value
            player.organizedCrimeUnavailableReason = nil
            if shouldNotifyOCReady(value), let value {
                notifier.send(title: "OC Ready! 💼", body: "\(value.name) is ready to execute", type: .ocReady)
            }
        case .unavailable(let message):
            player.organizedCrime = nil
            player.organizedCrimeUnavailableReason = message
        }
        if case .replace(let value) = payload.refills { player.refills = value }
        if case .replace(let value) = payload.education { player.education = value }
        if case .replace(let value) = payload.bounties {
            let incoming = payload.bountiesTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            player.bountiesFetchedAt = time.now
            player.bountiesCacheDelay = payload.bountiesDelay.map(TimeInterval.init)
            if incoming == nil || player.bountiesDataTimestamp == nil || incoming! > player.bountiesDataTimestamp! {
                player.bountiesDataTimestamp = incoming
                player.bountiesOnMe = value
                notifyBountiesOnMe()
            }
        }
        if case .replace(let counts) = payload.notifications {
            player.notificationCounts = counts
            player.unreadMessages = counts.messages
        }
    }

    func shouldNotifyOCReady(_ oc: OrganizedCrime2?) -> Bool {
        guard let oc, oc.isReady(at: serverNow) else { return false }
        return notificationCoordinator.shouldFireOnce(AlertKey.ocReady, epoch: "\(oc.id)")
    }

    /// `shouldFireOnce` tests and records, keyed by the bounty id, so each bounty
    /// announces itself once and stays quiet for as long as it hangs there.
    private func notifyBountiesOnMe() {
        let fresh = player.bountiesOnMe.filter {
            notificationCoordinator.shouldFireOnce(AlertKey.bounty($0.id), epoch: $0.id)
        }
        guard let banner = Self.bountyBanner(for: fresh) else { return }
        notifier.send(title: banner.title, body: banner.body, type: .bountyOnMe)
    }

    /// Several fresh bounties collapse into one summary banner rather than a stack.
    static func bountyBanner(for fresh: [Bounty]) -> (title: String, body: String)? {
        guard !fresh.isEmpty else { return nil }
        if fresh.count == 1 {
            let bounty = fresh[0]
            return ("⚠️ Bounty on you", "$\(TornFormatter.formatNumber(bounty.reward))\(bountyLister(bounty))")
        }
        return ("⚠️ \(fresh.count) bounties on you", "$\(bountyTotalAmount(fresh)) total")
    }

    /// Summed as Decimal: rewards are untrusted API integers and their total can exceed Int.
    static func bountyTotalAmount(_ bounties: [Bounty]) -> String {
        TornFormatter.formatNumber(bounties.reduce(Decimal.zero) { $0 + Decimal($1.reward) })
    }

    private static func bountyLister(_ bounty: Bounty) -> String {
        if bounty.isAnonymous == true { return " (anonymous)" }
        if let name = bounty.listerName { return " from \(name)" }
        return ""
    }
}
