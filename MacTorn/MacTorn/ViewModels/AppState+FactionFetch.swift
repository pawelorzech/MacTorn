import Foundation

extension AppState {
    func recordServiceFailure<Value>(_ result: TornServiceResult<Value>, for endpointID: String, since start: Date) {
        switch result {
        case .success:
            return
        case .apiError(let error, let bytes):
            handleAPIError(error, for: endpointID)
            recordHealth(endpointID, outcome: .error, since: start, bytes: bytes,
                         errorClass: error.classification.rawValue)
        case .httpError(let status, let bytes):
            recordHealth(endpointID, outcome: .error, since: start, bytes: bytes,
                         errorClass: "http\(status)")
        case .malformed(let bytes):
            recordHealth(endpointID, outcome: .error, since: start, bytes: bytes,
                         errorClass: "malformedResponse")
        }
    }

    private static var factionV2MinInterval: TimeInterval { 300 }

    // MARK: - Fetch Faction Data

    func fetchFactionData(apiKey: String, generation: UInt) async {
        guard let url = endpointURL("faction.basic", key: apiKey),
              reserveRequest("faction.basic") else { return }
        let startTime = Date()

        do {
            let result = try await factionService.loadBasic(from: url)
            guard isCurrentAccount(apiKey, generation: generation) else { return }

            if case .success(let payload, let responseBytes) = result {
                endpointGate.noteSuccess(for: "faction.basic")
                // Torn's `chain.timeout` is seconds remaining, not a timestamp. Resolve it
                // to an absolute server-clock expiry here, at the boundary, so every
                // consumer downstream keeps comparing it against `serverNow` — see
                // `FactionChain.resolvingExpiry`.
                let resolved = payload.resolvingChainExpiry(fetchedAt: Date(), clock: serverClock)
                factionService.publishBasic(resolved)
                // Chain data enters the app here — evaluate the expiry edge now, while
                // it is fresh. (Audit C-01: this used to be checked against the user
                // snapshot's `chain`, which Torn never populates.)
                checkChainNotification()
                logger.info("Faction data fetched")
                recordHealth("faction.basic", outcome: .ok, since: startTime, bytes: responseBytes)
            } else {
                recordServiceFailure(result, for: "faction.basic", since: startTime)
            }
        } catch {
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            recordHealth(
                "faction.basic",
                outcome: mapped?.classification == .offline ? .offline : .error,
                since: startTime,
                bytes: 0,
                errorClass: mapped?.classification.rawValue ?? "transport"
            )
            logger.warning("Faction fetch error (optional): \(String(describing: type(of: error)))")
        }
    }

    // MARK: - Fetch API v2 Faction Data

    func fetchFactionV2Data(apiKey: String, generation: UInt) async {
        guard !apiKey.isEmpty else { return }

        if let last = lastFactionV2Fetch,
           Date().timeIntervalSince(last) < Self.factionV2MinInterval {
            return
        }
        var issuedRequest = false

        if let url = endpointURL("faction.rankedwars", key: apiKey),
           reserveRequest("faction.rankedwars") {
            issuedRequest = true
            let startTime = Date()
            do {
                let result = try await factionService.loadWars(from: url)
                guard isCurrentAccount(apiKey, generation: generation) else { return }

                if case .success(let wars, let responseBytes) = result {
                    endpointGate.noteSuccess(for: "faction.rankedwars")
                    factionService.publishWars(wars)
                    recordHealth(
                        "faction.rankedwars",
                        outcome: .ok,
                        since: startTime,
                        bytes: responseBytes
                    )
                } else {
                    recordServiceFailure(result, for: "faction.rankedwars", since: startTime)
                }
            } catch {
                let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
                recordHealth(
                    "faction.rankedwars",
                    outcome: mapped?.classification == .offline ? .offline : .error,
                    since: startTime,
                    bytes: 0,
                    errorClass: mapped?.classification.rawValue ?? "transport"
                )
                logger.warning(
                    "Faction v2 (rankedwars) fetch error (optional): \(String(describing: type(of: error)))"
                )
            }
        }

        if !isRowSourcePaused("faction.news"), let url = endpointURL("faction.news", key: apiKey) {
            guard reserveRequest("faction.news") else {
                if issuedRequest { lastFactionV2Fetch = Date() }
                return
            }
            issuedRequest = true
            let startTime = Date()
            do {
                let result = try await factionService.loadNews(from: url)
                guard isCurrentAccount(apiKey, generation: generation) else { return }

                if case .success(let news, let responseBytes) = result {
                    endpointGate.noteSuccess(for: "faction.news")
                    factionService.publishNews(news)
                    recordHealth("faction.news", outcome: .ok, since: startTime, bytes: responseBytes)
                } else {
                    recordServiceFailure(result, for: "faction.news", since: startTime)
                }
            } catch {
                let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
                recordHealth(
                    "faction.news",
                    outcome: mapped?.classification == .offline ? .offline : .error,
                    since: startTime,
                    bytes: 0,
                    errorClass: mapped?.classification.rawValue ?? "transport"
                )
                logger.warning(
                    "Faction v2 (news) fetch error (optional): \(String(describing: type(of: error)))"
                )
            }
        }
        if issuedRequest, isCurrentAccount(apiKey, generation: generation) {
            lastFactionV2Fetch = Date()
        }
    }
}
