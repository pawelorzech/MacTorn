import XCTest
@testable import MacTorn

/// Etap B — the error taxonomy must classify Torn codes correctly and the backoff
/// ladder must obey its bounds.
final class TornAPIErrorTests: XCTestCase {

    // MARK: - Code classification

    func testIncorrectKeyIsPermanent() {
        XCTAssertEqual(TornAPIError.classify(code: 2, message: "Incorrect key").classification, .permanentKey)
    }

    /// Only the codes a user has to *act* on are permanent: an empty key, a wrong key,
    /// and a key its owner deliberately paused.
    func testOnlyUserActionableKeyCodesArePermanent() {
        XCTAssertEqual(TornAPIError.classify(code: 1, message: "").classification, .permanentKey)  // empty key
        XCTAssertEqual(TornAPIError.classify(code: 2, message: "").classification, .permanentKey)  // incorrect key
        XCTAssertEqual(TornAPIError.classify(code: 18, message: "").classification, .permanentKey) // paused by owner
    }

    /// The key codes that clear on their own must NOT halt the app. Torn's own names for
    /// these say so — "key owner in federal jail", "key change cooldown", "key temporary
    /// disabled". Classifying them as permanent told users to regenerate a key that was
    /// never broken, and left polling stopped until they did.
    func testSelfHealingKeyCodesAreTemporary() {
        for code in [10, 11, 12, 13] {
            let error = TornAPIError.classify(code: code, message: "")
            XCTAssertEqual(error.classification, .temporaryKey, "code \(code) should be temporary")
            XCTAssertFalse(error.haltsAllRequests, "code \(code) must not stop the app for good")
            XCTAssertNotNil(error.pauseDuration, "code \(code) needs a cool-off to retry after")
        }
    }

    /// A request that can never succeed as constructed disables its one endpoint. Retrying
    /// it at poll cadence is a guaranteed 100% failure rate against the request budget.
    func testMalformedRequestCodesDisableOnlyTheirEndpoint() {
        for code in [3, 4, 6, 7, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30] {
            let error = TornAPIError.classify(code: code, message: "")
            XCTAssertEqual(error.classification, .endpointUnavailable, "code \(code)")
            XCTAssertTrue(error.disablesEndpoint, "code \(code)")
            XCTAssertFalse(error.haltsAllRequests, "code \(code) must not stop the whole app")
        }
    }

    /// An IP block is the one failure where retrying at the normal cadence is what caused
    /// it, so it gets a cool-off an order of magnitude longer than a rate-limit blip.
    func testIPBlockBacksOffFarLongerThanARateLimit() {
        let block = TornAPIError.classify(code: 8, message: "")
        XCTAssertEqual(block.classification, .ipBlocked)
        let rateLimit = TornAPIError.classify(code: 5, message: "")
        XCTAssertGreaterThan(block.pauseDuration ?? 0, (rateLimit.pauseDuration ?? 0) * 10)
    }

    func testAccessLevelTooLowIsInsufficientPermissions() {
        let error = TornAPIError.classify(code: 16, message: "")
        XCTAssertEqual(error.classification, .insufficientPermissions)
        XCTAssertFalse(error.haltsAllRequests,
                       "selection-level permissions must refresh capabilities, not invalidate the key")
    }

    func testTooManyRequestsIsRateLimit() {
        XCTAssertEqual(TornAPIError.classify(code: 5, message: "").classification, .rateLimit)
    }

    func testDailyReadLimitIsDailyRowLimit() {
        XCTAssertEqual(TornAPIError.classify(code: 14, message: "").classification, .dailyRowLimit)
    }

    func testBackendCodesAreTemporary() {
        for code in [0, 9, 15, 17, 24, 31] {
            XCTAssertEqual(TornAPIError.classify(code: code, message: "").classification, .temporaryBackend,
                           "code \(code) should be temporary")
        }
    }

    /// A code Torn has not shipped yet must degrade into "retry later", never into a stop.
    func testUnknownFutureCodeDegradesToRetry() {
        let future = TornAPIError.classify(code: 999, message: "")
        XCTAssertEqual(future.classification, .temporaryBackend)
        XCTAssertFalse(future.haltsAllRequests)
    }

    func testTornCodeIsPreserved() {
        XCTAssertEqual(TornAPIError.classify(code: 14, message: "x").tornCode, 14)
        XCTAssertNil(TornAPIError.offline.tornCode)
    }

    // MARK: - Halt / retry semantics

    func testOnlyPermanentKeyErrorsHaltAllRequests() {
        XCTAssertTrue(TornAPIError.classify(code: 2, message: "").haltsAllRequests)
        XCTAssertFalse(TornAPIError.classify(code: 16, message: "").haltsAllRequests)
        XCTAssertTrue(TornAPIError.classify(code: 18, message: "").haltsAllRequests)
    }

    func testDailyRowLimitHaltsCategoryOnly() {
        let err = TornAPIError.classify(code: 14, message: "")
        XCTAssertTrue(err.haltsCategoryOnly)
        XCTAssertFalse(err.haltsAllRequests, "error 14 must NOT stop bars/countdowns")
    }

    // MARK: - Transport mapping

    func testTransportMapping() {
        XCTAssertEqual(TornAPIError.from(urlError: URLError(.cancelled)), .cancelled)
        XCTAssertEqual(TornAPIError.from(urlError: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(TornAPIError.from(urlError: URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(TornAPIError.from(urlError: URLError(.timedOut)).classification, .transport)
    }

    // MARK: - User message safety

    func testUserMessageStripsControlCharactersAndCaps() {
        let nasty = String(repeating: "A", count: 500) + "\n\n\rmalicious"
        let msg = TornAPIError.permanentKey(code: 2, message: nasty).userMessage
        XCTAssertLessThanOrEqual(msg.count, 120)
        XCTAssertFalse(msg.contains("\n"))
        XCTAssertFalse(msg.contains("\r"))
    }

    func testUserMessageNeverEmpty() {
        let cases: [TornAPIError] = [
            .permanentKey(code: 2, message: ""),
            .insufficientPermissions(code: 16, message: ""),
            .rateLimit(code: 5, message: ""),
            .dailyRowLimit(code: 14, message: ""),
            .temporaryBackend(code: 17, message: ""),
            .offline, .transport(detail: "x"), .malformedResponse(detail: "x"), .cancelled,
        ]
        for error in cases {
            XCTAssertFalse(error.userMessage.isEmpty, "\(error) has empty user message")
        }
    }

    // MARK: - Envelope classification (tornAPIError)

    func testEnvelopeV2Classifies() {
        let error = tornAPIError(in: ["code": 2, "error": "Incorrect key"])
        XCTAssertEqual(error?.classification, .permanentKey)
        XCTAssertEqual(error?.tornCode, 2)
    }

    func testEnvelopeV1Classifies() {
        let error = tornAPIError(in: ["error": ["code": 16, "error": "Access level too low"]])
        XCTAssertEqual(error?.classification, .insufficientPermissions)
    }

    func testEnvelopeDailyLimit() {
        let error = tornAPIError(in: ["code": 14, "error": "Daily read limit reached"])
        XCTAssertTrue(error!.haltsCategoryOnly)
        XCTAssertFalse(error!.haltsAllRequests)
    }

    func testNonEnvelopeReturnsNil() {
        XCTAssertNil(tornAPIError(in: ["player_id": 123, "name": "Someone", "money": 5000]))
    }
}
