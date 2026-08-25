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

/// One thread in a forum category listing. Only what the new-thread alert needs.
struct ForumCategoryThread: Equatable, Identifiable, Sendable {
    let id: Int
    let title: String
}

enum ForumCategoryResult {
    case success([ForumCategoryThread], responseBytes: Int)
    case apiError(TornAPIError, responseBytes: Int)
    case httpError(statusCode: Int, responseBytes: Int)
    case malformed(responseBytes: Int)
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
    func fetchCategoryThreads(from url: URL) async throws -> ForumCategoryResult
    func applyCategory(_ threads: [ForumCategoryThread]) -> [ForumCategoryThread]
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

    /// Set when a stored thread blob exists but could not be decoded. While true,
    /// `save()` will not overwrite it — the forum poll calls `save()` on its own
    /// schedule, so without this an unreadable blob was replaced by the empty in-memory
    /// list within one polling interval and the user's watched threads were gone for
    /// good (audit finding D-01). A deliberate add/remove/restore clears the flag.
    @ObservationIgnored private var threadsLoadFailed = false

    func load() {
        if let data = defaults.data(forKey: "forumWatchedThreads") {
            if let decoded = try? JSONDecoder().decode([WatchedThread].self, from: data) {
                threads = decoded
                threadsLoadFailed = false
            } else {
                threadsLoadFailed = true
                defaults.set(data, forKey: "forumWatchedThreads.unreadable")
            }
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
        if !threadsLoadFailed, let data = try? JSONEncoder().encode(threads) {
            defaults.set(data, forKey: "forumWatchedThreads")
        }
        // The config is a small, always-regenerable preference — no such guard needed.
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "forumWatchConfig")
        }
    }

    /// A deliberate user edit takes ownership of the list; persistence resumes.
    private func allowPersistenceAfterUserEdit() {
        threadsLoadFailed = false
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
        allowPersistenceAfterUserEdit()
        save()
        return threadID
    }

    func remove(threadID: Int) {
        threads.removeAll { $0.id == threadID }
        allowPersistenceAfterUserEdit()
        save()
    }

    func restore(_ thread: WatchedThread, at originalIndex: Int) -> Bool {
        guard !threads.contains(where: { $0.id == thread.id }) else { return false }
        let insertionIndex = min(max(originalIndex, 0), threads.count)
        threads.insert(thread, at: insertionIndex)
        allowPersistenceAfterUserEdit()
        save()
        return true
    }

    func toggleNotifications(threadID: Int) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].notificationsEnabled.toggle()
        allowPersistenceAfterUserEdit()
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

    /// Diffs a category listing against the ids already seen and returns only what is
    /// genuinely new.
    ///
    /// The first listing is *seeded*, never announced. `knownFactionThreadIds` starts
    /// empty, and a category holds up to a hundred threads — so treating an empty set as
    /// "everything here is new" would greet anyone switching the feature on with a hundred
    /// notifications about conversations that have been there for months.
    func applyCategory(_ threads: [ForumCategoryThread]) -> [ForumCategoryThread] {
        let ids = Set(threads.map(\.id))
        let wasSeeded = config.hasSeededFactionThreads
        defer {
            config.knownFactionThreadIds = ids
            config.hasSeededFactionThreads = true
            save()
        }
        guard wasSeeded else { return [] }
        return threads.filter { !config.knownFactionThreadIds.contains($0.id) }
    }

    func fetchCategoryThreads(from url: URL) async throws -> ForumCategoryResult {
        let request = TornAPIClient.request(for: url)
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
        guard let rows = json["threads"] as? [[String: Any]] else {
            return .malformed(responseBytes: data.count)
        }
        // A row without an id cannot be tracked, and one without a title cannot be
        // announced. Skip those rather than failing the whole listing over one bad row.
        let threads: [ForumCategoryThread] = rows.compactMap { row in
            guard let id = row["id"] as? Int else { return nil }
            let title = (row["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ForumCategoryThread(id: id, title: title ?? "Untitled thread")
        }
        return .success(threads, responseBytes: data.count)
    }

    func fetchThread(from url: URL) async throws -> ForumThreadResult {
        let request = TornAPIClient.request(for: url)
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
        // The post count is the whole point of this call, so a response without a
        // usable one is malformed — not a success with `postCount: 0`. Accepting the
        // zero wrote it into `lastKnownPostCount`, and the `previousCount > 0` guard in
        // `apply` then swallowed the next real increase: the "new posts" alert was lost
        // for good and the counter silently jumped (audit finding D-02).
        let postCount: Int
        if let count = thread["posts"] as? Int {
            postCount = count
        } else if let text = thread["posts"] as? String, let count = Int(text) {
            postCount = count   // tolerate a stringified number
        } else {
            return .malformed(responseBytes: data.count)
        }
        // Likewise, never overwrite a good title with a placeholder.
        let title = (thread["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return .success(
            ForumThreadSnapshot(
                title: title ?? "Unknown",
                postCount: postCount
            ),
            responseBytes: data.count
        )
    }
}
