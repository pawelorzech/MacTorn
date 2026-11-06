import Foundation

/// The one place MacTorn turns a built Torn API URL into the request it actually sends.
///
/// 1. On API v2 the key leaves the URL. Torn's OpenAPI document declares an
///    `Authorization: ApiKey <key>` header, and a key in a query string ends up in every logged,
///    cached or crash-reported URL. v1 has no documented header form, so v1 URLs keep `key=` and
///    `tornRedactedURL` remains the guard there.
/// 2. The URL cache is bypassed. Torn may already serve a response up to ~30 s old; stacking
///    `URLCache` on top of that leaves countdowns minutes stale.
enum TornAPIClient {
    /// Sent as `comment` on every request. Torn surfaces it in the key owner's key log
    /// (`/v2/key/log`), which is how a user tells MacTorn's calls apart from those of
    /// every other tool they have handed the same key to.
    static let comment = "MacTorn"

    /// Header name Torn documents for key auth.
    static let authorizationHeader = "Authorization"

    /// True for the `/v2/...` paths, the only ones where header auth is documented.
    static func usesHeaderAuth(_ url: URL) -> Bool {
        url.path.hasPrefix("/v2/") || url.path == "/v2"
    }

    /// Builds the request for `url`, relocating the key into the Authorization header
    /// where Torn supports it. Returns the URL unchanged when it carries no `key` item.
    static func request(for url: URL) -> URLRequest {
        guard usesHeaderAuth(url),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let key = items.first(where: { $0.name == "key" })?.value,
              !key.isEmpty
        else {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return request
        }

        let remaining = items.filter { $0.name != "key" }
        comps.queryItems = remaining.isEmpty ? nil : remaining
        var request = URLRequest(url: comps.url ?? url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("ApiKey \(key)", forHTTPHeaderField: authorizationHeader)
        return request
    }
}

/// Returns a log-safe description of an api.torn.com URL: scheme://host/path?[sorted-query-keys].
/// Strips every query *value* — Torn API keys travel in the `key` query param, so any
/// `absoluteString` interpolated into a log call would leak the key into os_log / Console.app.
/// Always use this instead of `url.absoluteString` in logger statements.
func tornRedactedURL(_ url: URL) -> String {
    let scheme = url.scheme ?? "?"
    let host = url.host ?? "?"
    let path = url.path
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let keys = (comps?.queryItems?.map(\.name).sorted() ?? []).joined(separator: ",")
    if keys.isEmpty {
        return "\(scheme)://\(host)\(path)"
    }
    return "\(scheme)://\(host)\(path)?[\(keys)]"
}

/// The classified Torn error in a response, or nil when the payload is not an error envelope.
/// Torn reports errors as HTTP 200 in two shapes, so the envelope, not the status code, is the
/// source of truth: v1 nests `{"error": {"code": Int, "error": String}}`, v2 puts `{"code": Int,
/// "error": String}` at the top level. Parsing only the v1 shape would swallow every v2 error.
func tornAPIError(in json: [String: Any]) -> TornAPIError? {
    if let nested = json["error"] as? [String: Any] {
        let code = nested["code"] as? Int ?? 0
        let message = nested["error"] as? String ?? ""
        return TornAPIError.classify(code: code, message: message)
    }
    if let code = json["code"] as? Int, let message = json["error"] as? String {
        return TornAPIError.classify(code: code, message: message)
    }
    return nil
}

enum TornServiceResult<Value> {
    case success(Value, responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case httpError(statusCode: Int, responseBytes: Int)
    case malformed(responseBytes: Int)
}

extension TornAPIClient {
    /// Transport and decoding run outside the main actor; only callers publish state.
    static func loadJSON<Value>(
        from url: URL,
        session: NetworkSession,
        decode: @Sendable (Data, [String: Any]) -> Value?
    ) async throws -> TornServiceResult<Value> {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request(for: url))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return .httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                              responseBytes: data.count)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let error = tornAPIError(in: json) {
            return .apiError(error, responseBytes: data.count)
        }
        guard let value = decode(data, json) else { return .malformed(responseBytes: data.count) }
        try Task.checkCancellation()
        return .success(value, responseBytes: data.count)
    }
}
