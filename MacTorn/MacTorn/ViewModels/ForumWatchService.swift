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
    func applyCategory(_ threads: [ForumCategoryThread], for categoryID: Int) -> [ForumCategoryThread]
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
    /// The first listing is *seeded*, never announced. The seen list starts empty, so
    /// treating "not in the list" as "new" on the first read would greet anyone switching
    /// the feature on with a page of notifications about conversations that have been
    /// there for months.
    func applyCategory(_ threads: [ForumCategoryThread], for categoryID: Int) -> [ForumCategoryThread] {
        // A listing that was in flight when the user changed the category describes a
        // category nobody is watching any more. Writing its ids under the new category's
        // seed would make the next poll treat a whole page of old threads as new.
        guard categoryID == config.factionForumCategoryId else { return [] }

        // Seeded ids belong to one category. Pointing the watch somewhere else starts over
        // rather than diffing against a category the user has left.
        let wasSeeded = config.hasSeededFactionThreads && config.seededCategoryId == categoryID
        let alreadySeen = wasSeeded ? Set(config.seenFactionThreadIds) : []
        let fresh = threads.filter { !alreadySeen.contains($0.id) }

        defer {
            // Union, most-recently-seen first. The listing is one capped page, so replacing
            // the set here would forget every thread below the cut and re-announce it the
            // next time a reply bumped it back up.
            var seen = threads.map(\.id)
            var known = Set(seen)
            for id in config.seenFactionThreadIds where !known.contains(id) {
                seen.append(id)
                known.insert(id)
            }
            config.seenFactionThreadIds = Array(seen.prefix(ForumWatchConfig.maximumSeenThreadIds))
            config.seededCategoryId = categoryID
            config.hasSeededFactionThreads = true
            save()
        }
        guard wasSeeded else { return [] }
        return fresh
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
            return ForumCategoryThread(id: id,
                                       title: ForumWatchService.boundedTitle(row["title"]) ?? "Untitled thread")
        }
        return .success(threads, responseBytes: data.count)
    }

    /// A forum title, trimmed and length-capped, or nil when there is nothing usable.
    ///
    /// Thread titles are server text that lands in `WatchedThread.title` and is encoded
    /// into the persisted `forumWatchedThreads` blob. Without a cap a hostile or MITM'd
    /// response writes unbounded text into the user's own data — and because that blob is
    /// protected by `threadsLoadFailed`, a blob too large to decode is deliberately never
    /// overwritten, so the bloat sticks instead of healing. Same rule the item catalog and
    /// typed watchlist names already follow.
    static func boundedTitle(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let cleaned = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WatchlistItem.maximumNameLength)
        )
        return cleaned.isEmpty ? nil : cleaned
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
        let title = ForumWatchService.boundedTitle(thread["title"])
        return .success(
            ForumThreadSnapshot(
                title: title ?? "Unknown",
                postCount: postCount
            ),
            responseBytes: data.count
        )
    }
}
