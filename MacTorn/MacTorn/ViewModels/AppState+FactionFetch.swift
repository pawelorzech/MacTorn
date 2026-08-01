import Foundation

extension AppState {
    private static var factionV2MinInterval: TimeInterval { 300 }

    // MARK: - Fetch Faction Data

    func fetchFactionData(apiKey: String, generation: UInt) async {
        guard let url = TornAPI.factionURL(for: apiKey),
              reserveRequest("faction.basic") else { return }
        let startTime = Date()

        do {
            let result = try await factionService.loadBasic(from: url)
            guard isCurrentAccount(apiKey, generation: generation) else { return }

            switch result {
            case .success(let payload, let responseBytes):
                factionService.publishBasic(payload)
                // Chain data enters the app here — evaluate the expiry edge now, while
                // it is fresh. (Audit C-01: this used to be checked against the user
                // snapshot's `chain`, which Torn never populates.)
                checkChainNotification()
                logger.info("Faction data fetched")
                recordHealth("faction.basic", outcome: .ok, since: startTime, bytes: responseBytes)

            case .apiError(let apiError, let responseBytes):
                recordHealth(
                    "faction.basic",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: apiError.classification.rawValue
                )
                logger.warning("Faction API error class: \(apiError.classification.rawValue)")

            case .httpError(let statusCode, let responseBytes):
                recordHealth(
                    "faction.basic",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: "http\(statusCode)"
                )

            case .malformed(let responseBytes):
                recordHealth(
                    "faction.basic",
                    outcome: .error,
                    since: startTime,
                    bytes: responseBytes,
                    errorClass: "malformedResponse"
                )
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

        if let url = TornAPI.factionRankedWarsURL(for: apiKey),
           reserveRequest("faction.rankedwars") {
            issuedRequest = true
            let startTime = Date()
            do {
                let result = try await factionService.loadWars(from: url)
                guard isCurrentAccount(apiKey, generation: generation) else { return }

                switch result {
                case .success(let wars, let responseBytes):
                    factionService.publishWars(wars)
                    recordHealth(
                        "faction.rankedwars",
                        outcome: .ok,
                        since: startTime,
                        bytes: responseBytes
                    )

                case .apiError(let apiError, let responseBytes):
                    recordHealth(
                        "faction.rankedwars",
                        outcome: .error,
                        since: startTime,
                        bytes: responseBytes,
                        errorClass: apiError.classification.rawValue
                    )
                    logger.warning(
                        "Faction v2 (rankedwars) API error class: \(apiError.classification.rawValue)"
                    )

                case .httpError(let statusCode, let responseBytes):
                    recordHealth(
                        "faction.rankedwars",
                        outcome: .error,
                        since: startTime,
                        bytes: responseBytes,
                        errorClass: "http\(statusCode)"
                    )

                case .malformed(let responseBytes):
                    recordHealth(
                        "faction.rankedwars",
                        outcome: .error,
                        since: startTime,
                        bytes: responseBytes,
                        errorClass: "malformedResponse"
                    )
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

        if !isRowSourcePaused("faction.news"), let url = TornAPI.factionNewsURL(for: apiKey) {
            guard reserveRequest("faction.news") else {
                if issuedRequest { lastFactionV2Fetch = Date() }
                return
            }
            issuedRequest = true
            let startTime = Date()
            do {
                let result = try await factionService.loadNews(from: url)
                guard isCurrentAccount(apiKey, generation: generation) else { return }

                switch result {
                case .success(let news, let responseBytes):
                    factionService.publishNews(news)
                    recordHealth("faction.news", outcome: .ok, since: startTime, bytes: responseBytes)

                case .apiError(let apiError, let responseBytes):
                    if apiError.haltsCategoryOnly {
                        pauseRowSource("faction.news", error: apiError)
                    }
                    recordHealth(
                        "faction.news",
                        outcome: .error,
                        since: startTime,
                        bytes: responseBytes,
                        errorClass: apiError.classification.rawValue
                    )
                    logger.warning(
                        "Faction v2 (news) API error class: \(apiError.classification.rawValue)"
                    )

                case .httpError(let statusCode, let responseBytes):
                    recordHealth(
                        "faction.news",
                        outcome: .error,
                        since: startTime,
                        bytes: responseBytes,
                        errorClass: "http\(statusCode)"
                    )

                case .malformed(let responseBytes):
                    recordHealth(
                        "faction.news",
                        outcome: .error,
                        since: startTime,
                        bytes: responseBytes,
                        errorClass: "malformedResponse"
                    )
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
