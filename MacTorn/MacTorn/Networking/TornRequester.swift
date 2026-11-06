import Foundation
import Observation
import os.log

private let requesterLogger = Logger(subsystem: TornConstants.logSubsystem, category: "TornRequester")

/// Why a request that was sent produced no value.
enum TornRequestFailure: Equatable, Sendable {
    case api(TornAPIError)
    /// A transport-level status other than 200. Torn reports key problems as HTTP 200
    /// with an error envelope, so this is the edge or the backend, never a bad key.
    case http(Int)
    case malformed
    /// `nil` when the thrown error was not a `URLError`.
    case transport(TornAPIError?)

    var errorClass: TornErrorClass {
        switch self {
        case .api(let error): return error.classification
        case .http: return .temporaryBackend
        case .malformed: return .malformedResponse
        case .transport(let error): return error?.classification ?? .transport
        }
    }

    var userMessage: String {
        switch self {
        case .api(let error): return error.userMessage
        case .http(let status): return TornAPIError.httpStatusMessage(status)
        case .malformed: return TornAPIError.malformedResponse(detail: "").userMessage
        case .transport(let error): return error?.userMessage ?? "Network request failed. Please try again."
        }
    }
}

enum TornFetch<Value> {
    case loaded(Value)
    /// Healthy, but Torn has nothing to serve right now (codes 32 / 33).
    case nothingToServe(code: Int)
    /// Nothing was sent: no key or URL, a gate denial, or the endpoint is not due yet.
    case skipped(TornEndpointDenial?)
    /// Sent and failed. Health, the gate and account-wide handling have already run.
    case failed(TornRequestFailure)
    /// The account changed or the task was cancelled; publish nothing.
    case superseded

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// A request that has been built and charged to the budget, waiting to be sent.
struct TornPreparedRequest: Sendable {
    let endpointID: String
    let url: URL
    let identity: AccountIdentity
    /// The key the URL carries. Account-wide errors only say something about the account
    /// when the request was made with the account's own key.
    let key: String
}

/// The one path every Torn request takes: build the URL for what the key can read, ask
/// the gate, charge the budget, send, classify the answer, record health, and hand
/// account-wide failures to the owner of the account.
@MainActor
@Observable
final class TornRequester {
    @ObservationIgnored let gate: TornEndpointGate
    @ObservationIgnored let budget: PollingCoordinator
    let health: EndpointHealthTracker
    /// What `/key/info` says this key can read. `nil` until known; the gate then allows
    /// everything rather than guessing.
    var keyInfo: TornKeyInfo?
    @ObservationIgnored var keyInfoLoadedAt: Date?
    private(set) var inFlight: [String: UUID] = [:]

    @ObservationIgnored let session: NetworkSession
    @ObservationIgnored private let time: TimeSource
    @ObservationIgnored private let account: AccountSessionStore
    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    /// Errors that refuse the whole account (bad or suspended key, rate limit, IP block,
    /// stale capabilities). Set by `AppState`, which owns polling.
    @ObservationIgnored var onAccountError: (TornAPIError, String) -> Void = { _, _ in }

    init(session: NetworkSession, time: TimeSource, account: AccountSessionStore,
         budget: PollingCoordinator? = nil) {
        self.session = session
        self.time = time
        self.account = account
        self.budget = budget ?? PollingCoordinator(time: time)
        self.gate = TornEndpointGate(time: time)
        self.health = EndpointHealthTracker(time: time)
    }

    /// Forgets everything learned about the previous account.
    func reset() {
        gate.reset()
        health.reset()
        keyInfo = nil
        keyInfoLoadedAt = nil
        lastAttempt.removeAll()
        inFlight.removeAll()
    }

    // MARK: - Asking

    func url(_ endpointID: String, parameter: Int? = nil, key: String? = nil) -> URL? {
        guard let endpoint = TornEndpointRegistry.endpoint(id: endpointID) else { return nil }
        let resolvedKey = key ?? account.apiKey
        guard !resolvedKey.isEmpty else { return nil }
        return endpoint.url(key: resolvedKey, parameter: parameter, granted: keyInfo?.grantedNames(for: endpoint))
    }

    func denial(_ endpointID: String) -> TornEndpointDenial? {
        gate.denial(for: endpointID, keyInfo: keyInfo, coordinator: budget)
    }

    /// Whether the endpoint's minimum interval has passed since it was last sent.
    func isDue(_ endpointID: String, every interval: TimeInterval? = nil) -> Bool {
        guard let interval = interval ?? TornEndpointRegistry.endpoint(id: endpointID)?.minimumInterval,
              let last = lastAttempt[endpointID] else { return true }
        return time.now.timeIntervalSince(last) >= interval
    }

    func makeDue(_ endpointIDs: [String]) {
        for id in endpointIDs { lastAttempt[id] = nil }
    }

    func isInFlight(_ endpointID: String) -> Bool { inFlight[endpointID] != nil }

    // MARK: - Sending

    /// Builds the URL and charges the budget now, on the caller's turn, so a request the
    /// caller has accepted is already counted before its transport runs.
    func prepare(_ endpointID: String, parameter: Int? = nil, query: [URLQueryItem] = [],
                 key: String? = nil) -> TornPreparedRequest? {
        let identity = account.identity
        let key = key ?? identity.apiKey
        guard var url = url(endpointID, parameter: parameter, key: key) else { return nil }
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + query
            guard let extended = components.url else { return nil }
            url = extended
        }
        guard reserve(endpointID) else { return nil }
        return TornPreparedRequest(endpointID: endpointID, url: url, identity: identity, key: key)
    }

    func fetch<Value>(_ endpointID: String, parameter: Int? = nil, query: [URLQueryItem] = [],
                      key: String? = nil,
                      decode: @escaping @Sendable (Data, [String: Any]) -> Value?) async -> TornFetch<Value> {
        guard !Task.isCancelled else { return .superseded }
        guard let request = prepare(endpointID, parameter: parameter, query: query, key: key) else {
            return .skipped(denial(endpointID))
        }
        return await send(request, decode: decode)
    }

    func send<Value>(_ request: TornPreparedRequest,
                     decode: @escaping @Sendable (Data, [String: Any]) -> Value?) async -> TornFetch<Value> {
        let session = self.session
        return await send(request) { url in
            try await TornAPIClient.loadJSON(from: url, session: session, decode: decode)
        }
    }

    /// `transport` turns the URL into a classified response; the user snapshot uses its own
    /// so it can stamp receipt before decoding off the main actor.
    func send<Value>(_ request: TornPreparedRequest,
                     transport: (URL) async throws -> TornServiceResult<Value>) async -> TornFetch<Value> {
        let id = request.endpointID
        let token = UUID()
        inFlight[id] = token
        defer { if inFlight[id] == token { inFlight[id] = nil } }
        let start = Date()
        let result: TornServiceResult<Value>
        do {
            result = try await transport(request.url)
        } catch {
            guard account.isCurrent(request.identity) else { return .superseded }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                record(id, .cancelled, since: start, bytes: 0)
                return .superseded
            }
            let mapped = (error as? URLError).map(TornAPIError.from(urlError:))
            record(id, mapped?.classification == .offline ? .offline : .error, since: start, bytes: 0,
                   errorClass: mapped?.classification ?? .transport)
            return .failed(.transport(mapped))
        }
        guard !Task.isCancelled, account.isCurrent(request.identity) else { return .superseded }
        return conclude(result, for: request, since: start)
    }

    private func conclude<Value>(_ result: TornServiceResult<Value>, for request: TornPreparedRequest,
                         since start: Date) -> TornFetch<Value> {
        let id = request.endpointID
        switch result {
        case .success(let value, let bytes):
            gate.noteSuccess(for: id)
            record(id, .ok, since: start, bytes: bytes)
            return .loaded(value)
        case .apiError(let error, let bytes) where error.classification == .notAvailable:
            gate.noteSuccess(for: id)
            record(id, .ok, since: start, bytes: bytes)
            return .nothingToServe(code: error.tornCode ?? 0)
        case .apiError(let error, let bytes):
            if error.isAccountWide, request.key == account.apiKey {
                // Handled before recording: a permanent-key halt resets account state, and
                // the failure that caused it must still be in the health readout afterwards.
                onAccountError(error, id)
                record(id, .error, since: start, bytes: bytes, errorClass: error.classification)
            } else {
                record(id, .error, since: start, bytes: bytes, errorClass: error.classification)
                gate.note(error, for: id)
                if let pause = error.pauseDuration {
                    requesterLogger.warning(
                        "Paused \(id) for \(Int(pause))s after \(error.classification.rawValue) (code \(error.tornCode ?? -1))"
                    )
                }
            }
            return .failed(.api(error))
        case .httpError(let status, let bytes):
            record(id, .error, since: start, bytes: bytes, errorClass: .temporaryBackend)
            return .failed(.http(status))
        case .malformed(let bytes):
            record(id, .error, since: start, bytes: bytes, errorClass: .malformedResponse)
            return .failed(.malformed)
        }
    }

    func record(_ endpointID: String, _ outcome: EndpointOutcome, since start: Date, bytes: Int,
                errorClass: TornErrorClass? = nil) {
        health.record(endpointID: endpointID, outcome: outcome,
                      latencyMs: Int(Date().timeIntervalSince(start) * 1000),
                      responseBytes: bytes, errorClass: errorClass)
    }

    private func reserve(_ endpointID: String) -> Bool {
        guard let endpoint = TornEndpointRegistry.endpoint(id: endpointID) else {
            requesterLogger.error("Request skipped for \(endpointID): not in the endpoint registry")
            return false
        }
        if let denial = denial(endpointID) {
            // Debug, not warning: a skip is the gate working, and a factionless player
            // would otherwise log "faction/basic denied" every thirty seconds.
            requesterLogger.debug("Request skipped for \(endpointID): \(denial.label)")
            return false
        }
        budget.record(endpoint)
        lastAttempt[endpointID] = time.now
        return true
    }
}
