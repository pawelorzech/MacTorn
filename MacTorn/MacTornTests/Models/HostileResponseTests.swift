import XCTest
import os.log
@testable import MacTorn

/// What a compromised or MITM'd Torn response can and cannot do to MacTorn's UI and to the
/// user's stored data.
///
/// Every case here was a real hole found in the 1.12.0 security audit. The sanitizers
/// filtered `CharacterSet.controlCharacters`, which is Unicode categories Cc and Cf only,
/// so U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR (categories Zl and Zp) walked
/// straight through and CoreText rendered both as hard line breaks. The item catalog wrote
/// unbounded server strings into the user's own watchlist.
final class HostileResponseTests: XCTestCase {

    /// Everything CoreText will break a line on. A sanitizer that misses any of these
    /// cannot promise a single-line notification.
    private let lineBreakers: [(name: String, scalar: String)] = [
        ("U+000A LINE FEED", "\u{000A}"),
        ("U+000D CARRIAGE RETURN", "\u{000D}"),
        ("U+0085 NEXT LINE", "\u{0085}"),
        ("U+2028 LINE SEPARATOR", "\u{2028}"),
        ("U+2029 PARAGRAPH SEPARATOR", "\u{2029}"),
    ]

    // MARK: - Notification spoofing

    func testNoLineBreakSurvivesNotificationSanitizing() {
        for breaker in lineBreakers {
            let sanitized = NotificationManager.sanitize("before\(breaker.scalar)after", maxLength: 200)
            XCTAssertEqual(sanitized, "beforeafter", "\(breaker.name) survived sanitizing")
        }
    }

    /// The attack this closes: a forum thread title becomes the entire notification body,
    /// so two paragraph separators buy an attacker a second paragraph that reads as though
    /// MacTorn wrote it.
    func testACraftedForumTitleCannotForgeASecondParagraph() {
        let hostile = "Re: raid tonight\u{2029}\u{2029}MacTorn: your API key expired, re-enter it at evil.example"
        let body = NotificationManager.sanitize(hostile, maxLength: 200)
        XCTAssertFalse(body.contains("\u{2029}"))
        XCTAssertEqual(body.components(separatedBy: .newlines).count, 1,
                       "the body must render as one line")
    }

    func testDirectionalOverrideIsStillStripped() {
        XCTAssertEqual(NotificationManager.sanitize("a\u{202E}b", maxLength: 200), "ab")
    }

    func testOrdinaryTitlesSurviveIntact() {
        let normal = "Re: raid tonight — 3 slots left (50% payout)"
        XCTAssertEqual(NotificationManager.sanitize(normal, maxLength: 200), normal)
    }

    func testLengthCapsStillApply() {
        let long = String(repeating: "A", count: 500)
        XCTAssertEqual(NotificationManager.sanitize(long, maxLength: 80).count, 80)
        XCTAssertEqual(NotificationManager.sanitize(long, maxLength: 200).count, 200)
    }

    // MARK: - Error copy

    /// `userMessage` returns Torn's own string verbatim for several codes and renders in
    /// the error bar of three views, so it needs the same rule.
    func testErrorMessagesCannotBreakOutOfOneLine() {
        for breaker in lineBreakers {
            let message = "Incorrect key\(breaker.scalar)MacTorn: enter a new key at evil.example"
            let shown = TornAPIError.permanentKey(code: 2, message: message).userMessage
            XCTAssertFalse(shown.contains(breaker.scalar), "\(breaker.name) reached the error bar")
            XCTAssertEqual(shown.components(separatedBy: .newlines).count, 1)
        }
    }

    // MARK: - Persisted data

    func testCatalogNamesAreCappedAtTheSameLengthAsTypedOnes() {
        let logger = Logger(subsystem: "com.mactorn.tests", category: "HostileResponse")
        let hostile = String(repeating: "A", count: 10_000)
        let data = try! JSONSerialization.data(withJSONObject: ["items": [["id": 1, "name": hostile]]])

        let parsed = AppState.parseItemCatalog(from: data, logger: logger)
        XCTAssertEqual(parsed[1]?.count, WatchlistItem.maximumNameLength)
    }

    func testCatalogIsBoundedSoOneResponseCannotBloatUserDefaults() {
        let logger = Logger(subsystem: "com.mactorn.tests", category: "HostileResponse")
        let flood = (1...(AppState.itemCatalogMaxEntries + 500)).map { ["id": $0, "name": "Item \($0)"] }
        let data = try! JSONSerialization.data(withJSONObject: ["items": flood])

        XCTAssertEqual(AppState.parseItemCatalog(from: data, logger: logger).count,
                       AppState.itemCatalogMaxEntries)
    }

    /// The backfill writes catalog names into the user's persisted watchlist, so it has to
    /// apply the trim and cap that typed names already got.
    func testRenamingAppliesTheSameTrimAndCapAsTyping() {
        let item = WatchlistItem(id: 206, name: "Item #206", lowestPrice: 0,
                                 lowestPriceQuantity: 0, secondLowestPrice: 0,
                                 lastUpdated: nil, error: nil)

        let long = item.renamed(to: String(repeating: "A", count: 500))
        XCTAssertEqual(long.name.count, WatchlistItem.maximumNameLength)

        let padded = item.renamed(to: "   Xanax   ")
        XCTAssertEqual(padded.name, "Xanax")
    }

    func testRenamingToNothingKeepsTheExistingName() {
        let item = WatchlistItem(id: 206, name: "Xanax", lowestPrice: 0,
                                 lowestPriceQuantity: 0, secondLowestPrice: 0,
                                 lastUpdated: nil, error: nil)
        XCTAssertEqual(item.renamed(to: "   ").name, "Xanax")
    }

    func testRenamingPreservesEverythingButTheName() {
        let item = WatchlistItem(id: 206, name: "Item #206", lowestPrice: 830_000,
                                 lowestPriceQuantity: 3, secondLowestPrice: 840_000,
                                 lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
                                 error: nil, priceThreshold: 800_000, lastAlertedPrice: 795_000)
        let renamed = item.renamed(to: "Xanax")

        XCTAssertEqual(renamed.id, 206)
        XCTAssertEqual(renamed.lowestPrice, 830_000)
        XCTAssertEqual(renamed.lowestPriceQuantity, 3)
        XCTAssertEqual(renamed.secondLowestPrice, 840_000)
        XCTAssertEqual(renamed.lastUpdated, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(renamed.priceThreshold, 800_000)
        XCTAssertEqual(renamed.lastAlertedPrice, 795_000)
    }

    // MARK: - Where an update link may point

    /// The release URL arrives from api.github.com and sits behind a button labelled
    /// "Download Update", so a swapped host would be MacTorn vouching for someone else.
    func testOnlyGitHubMayBeOfferedAsAnUpdateDownload() {
        XCTAssertTrue(UpdateManager.isTrustedReleaseURL("https://github.com/pawelorzech/MacTorn/releases/tag/v1.12.0"))
        XCTAssertTrue(UpdateManager.isTrustedReleaseURL("https://www.github.com/pawelorzech/MacTorn/releases"))

        for hostile in [
            "https://github.com.evil.example/pawelorzech/MacTorn/releases",
            "https://evil.example/github.com/releases",
            "http://github.com/pawelorzech/MacTorn/releases",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "not a url at all",
            "",
        ] {
            XCTAssertFalse(UpdateManager.isTrustedReleaseURL(hostile), "accepted \(hostile)")
        }
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertTrue(UpdateManager.isTrustedReleaseURL("https://GitHub.com/pawelorzech/MacTorn"))
        XCTAssertTrue(UpdateManager.isTrustedReleaseURL("HTTPS://github.com/pawelorzech/MacTorn"))
    }
}
