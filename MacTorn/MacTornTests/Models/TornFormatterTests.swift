import XCTest
@testable import MacTorn

final class TornFormatterTests: XCTestCase {
    func testFormatMoney_standardAmounts() {
        XCTAssertEqual(TornFormatter.formatMoney(0), "$0")
        XCTAssertEqual(TornFormatter.formatMoney(100), "$100")
        XCTAssertEqual(TornFormatter.formatMoney(1_000), "$1,000")
        XCTAssertEqual(TornFormatter.formatMoney(1_250_000), "$1,250,000")
        XCTAssertEqual(TornFormatter.formatMoney(50_000_000), "$50,000,000")
    }

    func testFormatMoney_negativeAmounts() {
        XCTAssertEqual(TornFormatter.formatMoney(-500), "-$500")
    }

    func testFormatNumber_standardNumbers() {
        XCTAssertEqual(TornFormatter.formatNumber(0), "0")
        XCTAssertEqual(TornFormatter.formatNumber(42), "42")
        XCTAssertEqual(TornFormatter.formatNumber(1_000), "1,000")
        XCTAssertEqual(TornFormatter.formatNumber(5_056_869), "5,056,869")
    }

    // MARK: - HTML stripping & entity decoding

    func testStrippedHTMLAndDecodedEntities_edgeCases() {
        XCTAssertEqual("  Plain ASCII text  ".strippedHTMLAndDecodedEntities, "Plain ASCII text")
        XCTAssertEqual(
            "You were mugged by <a href=\"profiles.php?XID=1\">Player</a> for $500 &amp; hospitalized.".strippedHTMLAndDecodedEntities,
            "You were mugged by Player for $500 & hospitalized."
        )
        XCTAssertEqual(
            "<b>&quot;Hi&quot;</b> &apos;a&#039; &lt;b&gt; &amp;lt;".strippedHTMLAndDecodedEntities,
            "\"Hi\" 'a' <b> <"
        )
        XCTAssertEqual("keep <> empty brackets".strippedHTMLAndDecodedEntities, "keep <> empty brackets")
        XCTAssertEqual("unclosed < tag stays".strippedHTMLAndDecodedEntities, "unclosed < tag stays")
        XCTAssertEqual("unknown &nbsp; entity stays".strippedHTMLAndDecodedEntities, "unknown &nbsp; entity stays")
        XCTAssertEqual("🎉 <b>Emoji &amp; UTF-8 café</b> 🚀".strippedHTMLAndDecodedEntities, "🎉 Emoji & UTF-8 café 🚀")
    }

    // MARK: - Display sanitization

    func testSanitizedForDisplay_fastPathAndUnicodeEdgeCases() {
        XCTAssertEqual("Clean ASCII".sanitizedForDisplay(limit: 50), "Clean ASCII")
        XCTAssertEqual("Clean ASCII".sanitizedForDisplay(limit: 5), "Clean")
        XCTAssertEqual("Clean ASCII".sanitizedForDisplay(limit: 0), "")
        XCTAssertEqual("Clean ASCII".sanitizedForDisplay(limit: -5), "")
        // Emoji ZWJ sequence is 1 grapheme cluster even though it spans multiple UTF-8 bytes & scalars.
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual("\(family)abc".sanitizedForDisplay(limit: 2), "\(family)a")
        XCTAssertEqual("a\u{202E}b\u{2028}c\u{200B}\(family)\nd".sanitizedForDisplay(limit: 20), "abc\(family)d")
        XCTAssertEqual("a\u{0000}b\u{007F}c".sanitizedForDisplay(limit: 20), "abc")
    }

    // MARK: - NextUpSection.when

    @MainActor
    func testNextUpSectionWhen_matchesExpectedDayBuckets() {
        let calendar = Calendar.current
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_780_000_000))!
        let laterToday = todayNoon.addingTimeInterval(3600)
        let tomorrow = todayNoon.addingTimeInterval(86_400)
        let inThreeDays = todayNoon.addingTimeInterval(86_400 * 3)

        let expectedTodayTime = laterToday.formatted(date: .omitted, time: .shortened)
        let expectedTomorrowTime = tomorrow.formatted(date: .omitted, time: .shortened)
        let expectedLaterTime = inThreeDays.formatted(date: .omitted, time: .shortened)
        let expectedWeekday = inThreeDays.formatted(.dateTime.weekday(.wide))

        XCTAssertEqual(NextUpSection.when(laterToday, from: todayNoon), "at \(expectedTodayTime)")
        XCTAssertEqual(NextUpSection.when(tomorrow, from: todayNoon), "tomorrow at \(expectedTomorrowTime)")
        XCTAssertEqual(NextUpSection.when(inThreeDays, from: todayNoon), "\(expectedWeekday) at \(expectedLaterTime)")

        // Crossing midnight invalidates the cached day window cleanly.
        let nextDayNoon = tomorrow
        XCTAssertEqual(NextUpSection.when(nextDayNoon.addingTimeInterval(600), from: nextDayNoon),
                       "at \(nextDayNoon.addingTimeInterval(600).formatted(date: .omitted, time: .shortened))")
    }
}
