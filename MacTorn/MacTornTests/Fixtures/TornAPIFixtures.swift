import Foundation

/// Sample JSON responses for testing
enum TornAPIFixtures {

    // MARK: - Full Response

    /// Function (not `static let`) so the top-level `server_time` is captured at
    /// the moment the test calls it, not at first-access of the type. The Torn
    /// API stamps every response with the current server time, and several
    /// tests assert on `endsAt = server_time + duration` against `Date()`, which
    /// fails if the fixture's clock froze ~60 s into the test run.
    ///
    /// NOTE: the live v1 `user` root anchors on `server_time` (not `timestamp`),
    /// verified against a real API response 2026-07-03 — fixtures mirror that.
    static func validFullResponse() -> [String: Any] { [
        "name": "TestPlayer",
        "player_id": 123456,
        "server_time": Int(Date().timeIntervalSince1970),
        "energy": [
            "current": 100,
            "maximum": 150,
            "increment": 5,
            "interval": 300,
            "ticktime": 60,
            "fulltime": 600
        ],
        "nerve": [
            "current": 50,
            "maximum": 60,
            "increment": 1,
            "interval": 300,
            "ticktime": 120,
            "fulltime": 1800
        ],
        "life": [
            "current": 7500,
            "maximum": 7500,
            "increment": 100,
            "interval": 300,
            "ticktime": 0,
            "fulltime": 0
        ],
        "happy": [
            "current": 5000,
            "maximum": 10000,
            "increment": 50,
            "interval": 300,
            "ticktime": 100,
            "fulltime": 30000
        ],
        "cooldowns": [
            "drug": 0,
            "medical": 0,
            "booster": 0
        ],
        "travel": [
            "destination": "Torn",
            "timestamp": 0,
            "departed": 0,
            "time_left": 0
        ],
        "status": [
            "description": "Okay",
            "details": "",
            "state": "Okay",
            "until": 0
        ],
        "chain": [
            "current": 0,
            "maximum": 10,
            "timeout": 0,
            "cooldown": 0
        ],
        "events": [
            "1": [
                "timestamp": 1700000000,
                "event": "You received a message from <a href='...'>Someone</a>",
                "seen": 0
            ]
        ],
        "messages": [
            "1": [
                "name": "TestSender",
                "type": "Private",
                "title": "Test Message",
                "timestamp": 1700000000,
                "read": 0
            ]
        ]
    ] }

    // MARK: - Bars

    static let energyFull: [String: Any] = [
        "current": 150,
        "maximum": 150,
        "increment": 5,
        "interval": 300,
        "ticktime": 0,
        "fulltime": 0
    ]

    static let energyHalf: [String: Any] = [
        "current": 75,
        "maximum": 150,
        "increment": 5,
        "interval": 300,
        "ticktime": 150,
        "fulltime": 4500
    ]

    static let energyEmpty: [String: Any] = [
        "current": 0,
        "maximum": 150,
        "increment": 5,
        "interval": 300,
        "ticktime": 300,
        "fulltime": 9000
    ]

    // MARK: - Travel

    static let travelInTorn: [String: Any] = [
        "destination": "Torn",
        "timestamp": 0,
        "departed": 0,
        "time_left": 0
    ]

    static let travelAbroad: [String: Any] = [
        "destination": "Mexico",
        "timestamp": 0,
        "departed": 0,
        "time_left": 0
    ]

    static let travelTraveling: [String: Any] = [
        "destination": "Japan",
        "timestamp": Int(Date().timeIntervalSince1970) + 600,
        "departed": Int(Date().timeIntervalSince1970) - 300,
        "time_left": 600
    ]

    // MARK: - Status

    static let statusOkay: [String: Any] = [
        "description": "Okay",
        "details": "",
        "state": "Okay",
        "until": 0
    ]

    static let statusHospital: [String: Any] = [
        "description": "In hospital for 30 minutes",
        "details": "Hospitalized by TestAttacker",
        "state": "Hospital",
        "until": Int(Date().timeIntervalSince1970) + 1800
    ]

    static let statusJail: [String: Any] = [
        "description": "In jail for 15 minutes",
        "details": "Jailed for assault",
        "state": "Jail",
        "until": Int(Date().timeIntervalSince1970) + 900
    ]

    // MARK: - Chain

    static let chainInactive: [String: Any] = [
        "current": 0,
        "maximum": 10,
        "timeout": 0,
        "cooldown": 0
    ]

    static let chainActive: [String: Any] = [
        "current": 25,
        "maximum": 100,
        "timeout": Int(Date().timeIntervalSince1970) + 300,
        "cooldown": 0
    ]

    static let chainOnCooldown: [String: Any] = [
        "current": 0,
        "maximum": 10,
        "timeout": 0,
        "cooldown": 3600
    ]

    // MARK: - Cooldowns

    /// Response with active cooldowns and a known top-level `server_time`,
    /// useful for asserting that `AppState.cooldownEnds` is computed as
    /// `server_time + duration` for each kind. (Param name kept as `timestamp`
    /// for call-site brevity; it populates the real `server_time` key.)
    static func responseWithCooldowns(
        timestamp: Int,
        drug: Int,
        booster: Int,
        medical: Int
    ) -> [String: Any] {
        var resp = validFullResponse()
        resp["server_time"] = timestamp
        resp["cooldowns"] = [
            "drug": drug,
            "medical": medical,
            "booster": booster
        ]
        return resp
    }

    // MARK: - Errors

    static let tornErrorInvalidKey: [String: Any] = [
        "error": [
            "code": 2,
            "error": "Incorrect Key"
        ]
    ]

    static let tornErrorRateLimit: [String: Any] = [
        "error": [
            "code": 5,
            "error": "Too many requests"
        ]
    ]

    // v2 error envelope — per Torn OpenAPI spec (https://api.torn.com/v2), error
    // schemas (ErrorTooManyRequests, ErrorIncorrectKey, …) expose `code` (int) and
    // `error` (string) as sibling TOP-LEVEL properties. This differs from the v1
    // envelope above, where `error` is a nested object. v2 endpoints (market, forum)
    // return this shape.
    static let tornErrorRateLimitV2: [String: Any] = [
        "code": 5,
        "error": "Too many requests"
    ]

    static let tornErrorInvalidKeyV2: [String: Any] = [
        "code": 2,
        "error": "Incorrect key"
    ]

    // MARK: - Money

    static let moneyData: [String: Any] = [
        "money_onhand": 1000000,
        "vault_amount": 50000000,
        "points": 5000,
        "donator": 100,
        "cayman_bank": 100000000
    ]

    // MARK: - Market

    static let marketItemSuccess: [String: Any] = [
        "itemmarket": [
            "listings": [
                ["price": 1000, "amount": 5],
                ["price": 1100, "amount": 3],
                ["price": 1200, "amount": 10]
            ]
        ],
        "bazaar": [
            ["cost": 950, "quantity": 2],
            ["cost": 1050, "quantity": 7]
        ]
    ]

    static let marketItemNoListings: [String: Any] = [
        "itemmarket": [
            "listings": []
        ],
        "bazaar": []
    ]

    // MARK: - API v2 User (organized crime 2.0, refills, education, bounties)

    /// Mirrors a live `/v2/user?selections=organizedcrime,refills,education,bounties`
    /// response (captured 2026-07-03). `ocReadyAt` places the OC's ready time relative
    /// to `now` so tests can drive both the "ready" and "counting down" states.
    static func userV2Response(
        ocReadyAt: Int = 1783158163,
        refillEnergy: Bool = true,
        studyingUntil: Int? = nil,
        bounties: [[String: Any]] = []
    ) -> [String: Any] {
        var education: [String: Any] = ["complete": [1, 2, 3]]
        education["current"] = studyingUntil.map { ["id": 12, "until": $0] } ?? NSNull()
        return [
            "organizedCrime": [
                "id": 1836033,
                "name": "Clinical Precision",
                "difficulty": 8,
                "status": "Planning",
                "created_at": 1782739952,
                "ready_at": ocReadyAt,
                "expired_at": 1783344752,
                "executed_at": NSNull(),
                "slots": [
                    ["position": "Imitator", "checkpoint_pass_rate": 75,
                     "user": ["id": 2362436, "progress": 100, "joined_at": 1782895791]],
                    ["position": "Cat Burglar", "checkpoint_pass_rate": 75,
                     "user": ["id": 1412840, "progress": 41.42, "joined_at": 1782812563]]
                ]
            ],
            "refills": ["energy": refillEnergy, "nerve": false, "token": false, "special_count": 0],
            "education": education,
            "bounties": bounties,
            "bounties_timestamp": 1783107206,
            "bounties_delay": 0
        ]
    }

    /// A single anonymous bounty placed on the signed-in player (id 2362436).
    static func bountyOnMe(targetId: Int = 2362436, reward: Int = 2_500_000) -> [String: Any] {
        [
            "target_id": targetId, "target_name": "TestPlayer", "target_level": 50,
            "lister_id": NSNull(), "lister_name": NSNull(),
            "reward": reward, "reason": NSNull(), "quantity": 1,
            "is_anonymous": true, "valid_until": 1790000000
        ]
    }

    // MARK: - API v2 Faction (ranked wars, news)

    /// Mirrors `/v2/faction/rankedwars` (captured 2026-07-03): one active war
    /// (`end == 0`) plus one finished war. Faction 11559 = The Masters.
    static func rankedWarsResponse() -> [String: Any] {
        [
            "rankedwars": [
                [
                    "id": 44751, "start": 1783083600, "end": 0, "target": 13000, "winner": NSNull(),
                    "factions": [
                        ["id": 11559, "name": "The Masters", "score": 9890, "chain": 0],
                        ["id": 37498, "name": "The Railroad", "score": 3643, "chain": 0]
                    ]
                ],
                [
                    "id": 43781, "start": 1781000000, "end": 1781967435, "target": 9900, "winner": 36457,
                    "factions": [
                        ["id": 11559, "name": "The Masters", "score": 8942, "chain": 0],
                        ["id": 36457, "name": "Warband", "score": 18848, "chain": 0]
                    ]
                ]
            ]
        ]
    }

    /// Mirrors `/v2/faction/news?cat=main` — text is HTML with profile/faction links.
    static let factionNewsResponse: [String: Any] = [
        "news": [
            ["id": "zL8X", "text": "<a href='/profiles.php?XID=889354'>Steven</a> disabled war mode",
             "timestamp": 1783102710],
            ["id": "8Mn2", "text": "<a href='/profiles.php?XID=2676448'>Lord</a> enabled war mode",
             "timestamp": 1783080225]
        ]
    ]

    // MARK: - Stocks

    // Real Torn API shape: outer `stocks` is a dict keyed by stock_id,
    // and inner `transactions` is a dict keyed by transaction_id.
    static let stocksData: [String: Any] = [
        "stocks": [
            "1": [
                "stock_id": 1,
                "total_shares": 10000,
                "transactions": [
                    "1234": ["shares": 5000, "bought_price": 500, "time_bought": 1700000000],
                    "1235": ["shares": 5000, "bought_price": 600, "time_bought": 1700100000]
                ]
            ],
            "2": [
                "stock_id": 25,
                "total_shares": 500,
                "transactions": [
                    "2001": ["shares": 500, "bought_price": 1000, "time_bought": 1700200000]
                ]
            ]
        ]
    ]

    // MARK: - Helper Methods

    // MARK: - Forum Fixtures

    static let forumThreadSuccess: [String: Any] = [
        "thread": [
            "id": 12345,
            "title": "Test Forum Thread",
            "posts": 42,
            "last_post_time": 1700000000,
            "is_locked": false,
            "author": [
                "id": 123456,
                "username": "TestPlayer"
            ]
        ]
    ]

    static let forumThreadUpdated: [String: Any] = [
        "thread": [
            "id": 12345,
            "title": "Test Forum Thread",
            "posts": 45,
            "last_post_time": 1700001000,
            "is_locked": false,
            "author": [
                "id": 123456,
                "username": "TestPlayer"
            ]
        ]
    ]

    static let forumCategoryThreads: [String: Any] = [
        "threads": [
            [
                "id": 100,
                "title": "Faction Thread 1",
                "posts": 10,
                "first_post_time": 1699990000,
                "last_post_time": 1700000000,
                "author": ["id": 111, "username": "FactionMember1"]
            ],
            [
                "id": 200,
                "title": "Faction Thread 2",
                "posts": 5,
                "first_post_time": 1699995000,
                "last_post_time": 1699999000,
                "author": ["id": 222, "username": "FactionMember2"]
            ]
        ]
    ]

    // MARK: - Helpers

    static func toData(_ json: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: json)
    }

    static func toString(_ json: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }
}
