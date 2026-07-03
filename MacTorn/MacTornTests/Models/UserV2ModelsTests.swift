import XCTest
@testable import MacTorn

/// Models decoded from the combined v2 `/user` call: refills, education, bounties.
/// JSON shapes mirror live API responses captured 2026-07-03.
final class UserV2ModelsTests: XCTestCase {

    // MARK: - Refills

    func testRefills_decodesLiveShape() throws {
        let json: [String: Any] = ["energy": true, "nerve": false, "token": false, "special_count": 0]
        let data = try JSONSerialization.data(withJSONObject: json)
        let refills = try JSONDecoder().decode(Refills.self, from: data)

        XCTAssertTrue(refills.energy)
        XCTAssertFalse(refills.nerve)
        XCTAssertFalse(refills.token)
        XCTAssertEqual(refills.specialCount, 0)
    }

    func testRefills_unclaimed_listsOnlyUnusedRefills() {
        XCTAssertEqual(Refills(energy: true, nerve: false, token: false).unclaimed, ["Nerve", "Token"])
        XCTAssertEqual(Refills(energy: false, nerve: false, token: false).unclaimed, ["Energy", "Nerve", "Token"])
        XCTAssertTrue(Refills(energy: true, nerve: true, token: true).unclaimed.isEmpty,
                      "all claimed → nothing to nudge about")
    }

    // MARK: - Education

    func testEducation_notStudying_whenCurrentNull() throws {
        let json: [String: Any] = ["complete": [1, 2, 3], "current": NSNull()]
        let data = try JSONSerialization.data(withJSONObject: json)
        let edu = try JSONDecoder().decode(EducationStatus.self, from: data)

        XCTAssertEqual(edu.complete, [1, 2, 3])
        XCTAssertFalse(edu.isStudying)
        XCTAssertNil(edu.endsDate)
    }

    func testEducation_studying_exposesEndDate() throws {
        let until = 1_790_000_000
        let json: [String: Any] = ["complete": [1, 2], "current": ["id": 12, "until": until]]
        let data = try JSONSerialization.data(withJSONObject: json)
        let edu = try JSONDecoder().decode(EducationStatus.self, from: data)

        XCTAssertTrue(edu.isStudying)
        XCTAssertEqual(edu.endsDate, Date(timeIntervalSince1970: TimeInterval(until)))
    }

    // MARK: - Bounty

    func testBounty_decodesAnonymousBounty_withNullLister() throws {
        let data = try JSONSerialization.data(withJSONObject: TornAPIFixtures.bountyOnMe(reward: 2_500_000))
        let bounty = try JSONDecoder().decode(Bounty.self, from: data)

        XCTAssertEqual(bounty.targetId, 2362436)
        XCTAssertEqual(bounty.reward, 2_500_000)
        XCTAssertEqual(bounty.isAnonymous, true)
        XCTAssertNil(bounty.listerName, "anonymous bounty → null lister must decode as nil, not crash")
        XCTAssertNil(bounty.listerId)
    }

    func testBounty_id_isStableCompositeKey() throws {
        let data = try JSONSerialization.data(withJSONObject: TornAPIFixtures.bountyOnMe(reward: 999))
        let bounty = try JSONDecoder().decode(Bounty.self, from: data)
        XCTAssertEqual(bounty.id, "2362436-999-0-1790000000")
    }

    // MARK: - Ranked War

    private func decodeRankedWars() throws -> [RankedWar] {
        let arr = TornAPIFixtures.rankedWarsResponse()["rankedwars"] as! [[String: Any]]
        let data = try JSONSerialization.data(withJSONObject: arr)
        return try JSONDecoder().decode([RankedWar].self, from: data)
    }

    func testRankedWar_activeWar_identifiesMyFactionAndOpponent() throws {
        let wars = try decodeRankedWars()
        let active = try XCTUnwrap(wars.first { $0.isActive })

        XCTAssertEqual(active.id, 44751)
        XCTAssertEqual(active.target, 13000)
        XCTAssertNil(active.winner, "an ongoing war has no winner")
        XCTAssertEqual(active.faction(id: 11559)?.score, 9890, "my faction's score")
        XCTAssertEqual(active.opponent(of: 11559)?.id, 37498, "the other faction is the opponent")
    }

    func testRankedWar_finishedWar_isNotActive() throws {
        let wars = try decodeRankedWars()
        let finished = try XCTUnwrap(wars.first { $0.id == 43781 })
        XCTAssertFalse(finished.isActive, "a war with an end timestamp is over")
        XCTAssertEqual(finished.winner, 36457)
    }

    // MARK: - Faction News

    func testFactionNews_plainText_stripsHTMLAndEntities() throws {
        let json: [String: Any] = [
            "id": "x",
            "text": "<a href='/profiles.php?XID=1'>Steven</a> attacked &amp; won",
            "timestamp": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let news = try JSONDecoder().decode(FactionNews.self, from: data)
        XCTAssertEqual(news.plainText, "Steven attacked & won")
    }
}
