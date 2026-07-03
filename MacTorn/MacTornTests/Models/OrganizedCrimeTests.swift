import XCTest
@testable import MacTorn

/// Tests the Organized Crime 2.0 model (`OrganizedCrime2`), the player's own current
/// OC read from v2 `/user?selections=organizedcrime`. The legacy v1 `faction/crimes`
/// (OC 1.0) selection is dead: it now returns only frozen pre-migration history and its
/// `initiated` field flipped Bool→Int, so the old parser silently dropped everything.
/// JSON below mirrors a live API response captured 2026-07-03.
final class OrganizedCrimeTests: XCTestCase {

    /// A trimmed but faithful copy of the live `organizedCrime` object.
    private func liveOCJSON(readyAt: Int, executedAt: Int? = nil) -> [String: Any] {
        var json: [String: Any] = [
            "id": 1836033,
            "name": "Clinical Precision",
            "difficulty": 8,
            "status": "Planning",
            "created_at": 1782739952,
            "planning_at": 1782812563,
            "ready_at": readyAt,
            "expired_at": 1783344752,
            "slots": [
                ["position": "Imitator",
                 "checkpoint_pass_rate": 75,
                 "user": ["id": 2362436, "progress": 100, "joined_at": 1782895791]],
                ["position": "Cat Burglar",
                 "checkpoint_pass_rate": 75,
                 "user": ["id": 1412840, "progress": 41.42, "joined_at": 1782812563]],
                ["position": "Assassin",
                 "checkpoint_pass_rate": 79,
                 "user": NSNull()]
            ]
        ]
        if let executedAt { json["executed_at"] = executedAt }
        return json
    }

    func testOrganizedCrime2_decodesFromLiveShape() throws {
        let data = try JSONSerialization.data(withJSONObject: liveOCJSON(readyAt: 1783158163))
        let oc = try JSONDecoder().decode(OrganizedCrime2.self, from: data)

        XCTAssertEqual(oc.id, 1836033)
        XCTAssertEqual(oc.name, "Clinical Precision")
        XCTAssertEqual(oc.difficulty, 8)
        XCTAssertEqual(oc.status, "Planning")
        XCTAssertEqual(oc.readyAt, 1783158163)
        XCTAssertEqual(oc.totalSlots, 3)
        XCTAssertEqual(oc.filledSlots, 2, "third slot has a null user → unfilled")
    }

    func testOrganizedCrime2_myProgress_returnsSignedInPlayerSlot() throws {
        let data = try JSONSerialization.data(withJSONObject: liveOCJSON(readyAt: 1783158163))
        let oc = try JSONDecoder().decode(OrganizedCrime2.self, from: data)

        XCTAssertEqual(oc.myProgress(playerId: 2362436), 100)
        let fractional = try XCTUnwrap(oc.myProgress(playerId: 1412840))
        XCTAssertEqual(fractional, 41.42, accuracy: 0.001, "fractional progress must decode as Double")
        XCTAssertNil(oc.myProgress(playerId: 999999), "player not in this OC → nil")
    }

    func testOrganizedCrime2_isReady_whenReadyPastAndNotExecuted() throws {
        let past = Int(Date().timeIntervalSince1970) - 100
        let data = try JSONSerialization.data(withJSONObject: liveOCJSON(readyAt: past))
        let oc = try JSONDecoder().decode(OrganizedCrime2.self, from: data)
        XCTAssertTrue(oc.isReady)
    }

    func testOrganizedCrime2_notReady_whenReadyInFuture() throws {
        let future = Int(Date().timeIntervalSince1970) + 3600
        let data = try JSONSerialization.data(withJSONObject: liveOCJSON(readyAt: future))
        let oc = try JSONDecoder().decode(OrganizedCrime2.self, from: data)
        XCTAssertFalse(oc.isReady)
    }

    func testOrganizedCrime2_notReady_whenAlreadyExecuted() throws {
        let past = Int(Date().timeIntervalSince1970) - 100
        let data = try JSONSerialization.data(
            withJSONObject: liveOCJSON(readyAt: past, executedAt: past + 10)
        )
        let oc = try JSONDecoder().decode(OrganizedCrime2.self, from: data)
        XCTAssertFalse(oc.isReady, "an executed OC is no longer 'ready to execute'")
    }
}
