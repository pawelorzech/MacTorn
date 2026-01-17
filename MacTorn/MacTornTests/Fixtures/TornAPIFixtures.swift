import Foundation

/// Sample JSON responses for testing
enum TornAPIFixtures {

    // MARK: - Full Response

    static let validFullResponse: [String: Any] = [
        "name": "TestPlayer",
        "player_id": 123456,
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
    ]

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

    // MARK: - Money

    static let moneyData: [String: Any] = [
        "money_onhand": 1000000,
        "vault_amount": 50000000,
        "points": 5000,
        "company_funds": 100,
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

    // MARK: - Helper Methods

    static func toData(_ json: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: json)
    }

    static func toString(_ json: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
    }
}
