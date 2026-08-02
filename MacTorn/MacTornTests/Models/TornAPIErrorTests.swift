import XCTest
@testable import MacTorn

/// Etap B — the error taxonomy must classify Torn codes correctly and the backoff
/// ladder must obey its bounds.
final class TornAPIErrorTests: XCTestCase {

    // MARK: - Code classification

    func testIncorrectKeyIsPermanent() {
        XCTAssertEqual(TornAPIError.classify(code: 2, message: "Incorrect key").classification, .permanentKey)
    }

    func testPausedAndDisabledKeysArePermanent() {
        XCTAssertEqual(TornAPIError.classify(code: 18, message: "").classification, .permanentKey) // paused by owner
        XCTAssertEqual(TornAPIError.classify(code: 13, message: "").classification, .permanentKey) // owner inactive
        XCTAssertEqual(TornAPIError.classify(code: 1, message: "").classification, .permanentKey)  // empty key
    }

    func testAccessLevelTooLowIsInsufficientPermissions() {
        XCTAssertEqual(TornAPIError.classify(code: 16, message: "").classification, .insufficientPermissions)
    }

    func testTooManyRequestsIsRateLimit() {
        XCTAssertEqual(TornAPIError.classify(code: 5, message: "").classification, .rateLimit)
    }

    func testDailyReadLimitIsDailyRowLimit() {
        XCTAssertEqual(TornAPIError.classify(code: 14, message: "").classification, .dailyRowLimit)
    }

    func testBackendCodesAreTemporary() {
        for code in [0, 8, 9, 15, 17, 24, 999] {
            XCTAssertEqual(TornAPIError.classify(code: code, message: "").classification, .temporaryBackend,
                           "code \(code) should be temporary")
        }
    }

    func testTornCodeIsPreserved() {
        XCTAssertEqual(TornAPIError.classify(code: 14, message: "x").tornCode, 14)
        XCTAssertNil(TornAPIError.offline.tornCode)
    }

    // MARK: - Halt / retry semantics (Etap C: 2, 16, 18 halt; 14 halts category only)

    func testKeyAndPermissionErrorsHaltAllRequests() {
        XCTAssertTrue(TornAPIError.classify(code: 2, message: "").haltsAllRequests)
        XCTAssertTrue(TornAPIError.classify(code: 16, message: "").haltsAllRequests)
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
