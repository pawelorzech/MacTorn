import Foundation
import Observation

struct ForumThreadSnapshot: Equatable {
    let title: String
    let postCount: Int
}

enum ForumThreadResult {
    case success(ForumThreadSnapshot, responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case httpError(statusCode: Int, responseBytes: Int)
    case malformed(responseBytes: Int)
}

struct ForumNewPosts: Equatable {
    let threadID: Int
    let title: String
    let count: Int
}

@MainActor
protocol ForumWatchServicing: AnyObject {
    var threads: [WatchedThread] { get set }
    var config: ForumWatchConfig { get set }

    func load()
    func save()
    func parseThreadInput(_ input: String) -> Int?
    func add(input: String) -> Int?
    func remove(threadID: Int)
    func restore(_ thread: WatchedThread, at originalIndex: Int) -> Bool
    func toggleNotifications(threadID: Int)
    func markAsRead(threadID: Int)
    func apply(_ snapshot: ForumThreadSnapshot, to threadID: Int) -> ForumNewPosts?
    func setError(_ error: String, for threadID: Int)
    func fetchThread(from url: URL) async throws -> ForumThreadResult
}

/// Owns forum-watch state, config, persistence and response decoding. Poll timers,
/// bounded fan-out, account cancellation, budgets and notifications stay in AppState.
@MainActor
@Observable
final class ForumWatchService: ForumWatchServicing {
    var threads: [WatchedThread] = []
    var config = ForumWatchConfig()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: NetworkSession

    init(defaults: UserDefaults, session: NetworkSession) {
        self.defaults = defaults
        self.session = session
    }

    func load() {
        if let data = defaults.data(forKey: "forumWatchedThreads"),
           let decoded = try? JSONDecoder().decode([WatchedThread].self, from: data) {
            threads = decoded
        }
        if let data = defaults.data(forKey: "forumWatchConfig"),
           let decoded = try? JSONDecoder().decode(ForumWatchConfig.self, from: data) {
            config = decoded
            if ![120, 180, 300].contains(config.pollingIntervalSeconds) {
                config.pollingIntervalSeconds = 180
            }
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(threads) {
            defaults.set(data, forKey: "forumWatchedThreads")
        }
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "forumWatchConfig")
        }
    }

    func parseThreadInput(_ input: String) -> Int? {
        func valid(_ id: Int?) -> Int? {
            guard let id, id > 0 else { return nil }
            return id
        }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(trimmed) {
            return valid(id)
        }
        guard let range = trimmed.range(
            of: #"[?&#]t=(\d+)"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let match = trimmed[range]
        return valid(Int(match.drop(while: { !$0.isNumber })))
    }

    func add(input: String) -> Int? {
        guard let threadID = parseThreadInput(input),
              !threads.contains(where: { $0.id == threadID }) else {
            return nil
        }
        threads.append(
            WatchedThread(
                id: threadID,
                title: "Loading...",
                lastKnownPostCount: 0
            )
        )
        save()
        return threadID
    }

    func remove(threadID: Int) {
        threads.removeAll { $0.id == threadID }
        save()
    }

    func restore(_ thread: WatchedThread, at originalIndex: Int) -> Bool {
        guard !threads.contains(where: { $0.id == thread.id }) else { return false }
        let insertionIndex = min(max(originalIndex, 0), threads.count)
        threads.insert(thread, at: insertionIndex)
        save()
        return true
    }

    func toggleNotifications(threadID: Int) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].notificationsEnabled.toggle()
        save()
    }

    func markAsRead(threadID: Int) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].error = nil
        save()
    }

    func apply(_ snapshot: ForumThreadSnapshot, to threadID: Int) -> ForumNewPosts? {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return nil }
        let previousCount = threads[index].lastKnownPostCount
        threads[index].title = snapshot.title
        threads[index].lastChecked = Date()
        threads[index].error = nil
        threads[index].lastKnownPostCount = snapshot.postCount

        guard previousCount > 0,
              snapshot.postCount > previousCount,
              threads[index].notificationsEnabled else {
            return nil
        }
        return ForumNewPosts(
            threadID: threadID,
            title: snapshot.title,
            count: snapshot.postCount - previousCount
        )
    }

    func setError(_ error: String, for threadID: Int) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].error = error
    }

    func fetchThread(from url: URL) async throws -> ForumThreadResult {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return .httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                responseBytes: data.count
            )
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .malformed(responseBytes: data.count)
        }
        if let apiError = tornAPIError(in: json) {
            return .apiError(apiError, responseBytes: data.count)
        }
        let thread = json["thread"] as? [String: Any] ?? json
        guard thread["title"] != nil || thread["posts"] != nil else {
            return .malformed(responseBytes: data.count)
        }
        return .success(
            ForumThreadSnapshot(
                title: thread["title"] as? String ?? "Unknown",
                postCount: thread["posts"] as? Int ?? 0
            ),
            responseBytes: data.count
        )
    }
}
