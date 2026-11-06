import Foundation
import Observation

struct ForumThreadSnapshot: Equatable {
    let title: String
    let postCount: Int
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

/// Owns forum-watch state, config, persistence and response decoding. Poll timers,
/// bounded fan-out, account cancellation, budgets and notifications stay in AppState.
@MainActor
@Observable
final class ForumWatchService {
    var threads: [WatchedThread] = []
    var config = ForumWatchConfig() {
        didSet { onConfigChanged() }
    }
    /// AppState re-times the forum poll through this when the cadence changes.
    @ObservationIgnored var onConfigChanged: () -> Void = {}

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    @ObservationIgnored private var storedThreads = PersistedList<WatchedThread>(key: "forumWatchedThreads")
    private static let configKey = "forumWatchConfig"

    func load() {
        if let saved = storedThreads.load(from: defaults) { threads = saved }
        if let decoded = defaults.decoded(ForumWatchConfig.self, forKey: Self.configKey) {
            config = decoded
            if !ForumWatchConfig.pollingIntervals.contains(config.pollingIntervalSeconds) {
                config.pollingIntervalSeconds = ForumWatchConfig.defaultPollingInterval
            }
        }
    }

    func save() {
        storedThreads.save(threads, to: defaults)
        // The config is a small, always-regenerable preference, so it needs no such guard.
        defaults.setEncoded(config, forKey: Self.configKey)
    }

    private func allowPersistenceAfterUserEdit() {
        storedThreads.userEdited()
    }

    func setPollingInterval(_ seconds: Int) {
        config.pollingIntervalSeconds = seconds
        save()
    }

    /// Turning the watch off forgets which threads it had seen, so switching it back on
    /// seeds again rather than announcing everything posted meanwhile.
    func setCategoryMonitoring(_ enabled: Bool) {
        config.factionForumAutoMonitor = enabled
        if !enabled { config.forgetSeenThreads() }
        save()
    }

    /// A different category is a different set of threads; the old seen-ids would mark
    /// every thread in the new one as already known.
    func setCategory(_ categoryID: Int?) {
        guard categoryID != config.factionForumCategoryId else { return }
        config.factionForumCategoryId = categoryID
        config.forgetSeenThreads()
        save()
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
        guard threads.reinsert(thread, at: originalIndex) else { return false }
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
        if threads[index].lastChecked == nil, threads[index].title == "Loading..." {
            threads[index].title = "Thread #\(threadID)"
        }
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

    nonisolated static func decodeCategoryThreads(_ data: Data, _ json: [String: Any]) -> [ForumCategoryThread]? {
        guard let rows = json["threads"] as? [[String: Any]] else {
            return nil
        }
        // A row without an id cannot be tracked, and one without a title cannot be announced; skip those
        // rather than failing the whole listing over one bad row. The rows read are capped too: `limit=20`
        // is only a request parameter a remote server need not honour, and a listing longer than
        // `maximumSeenThreadIds` would make every poll evict the tail and re-announce it on the next.
        let threads: [ForumCategoryThread] = rows.prefix(ForumWatchService.maximumThreadsPerListing).compactMap { row in
            guard let id = row["id"] as? Int else { return nil }
            return ForumCategoryThread(id: id,
                                       title: ForumWatchService.boundedTitle(row["title"]) ?? "Untitled thread")
        }
        return threads
    }

    /// Most rows MacTorn will accept from one category listing.
    ///
    /// Generous against the 20 rows the request asks for, and far below
    /// `ForumWatchConfig.maximumSeenThreadIds` so the seen list can always hold several
    /// pages. That gap is what stops eviction and the page from oscillating.
    nonisolated static let maximumThreadsPerListing = 100

    /// A forum title, trimmed and length-capped, or nil when there is nothing usable.
    ///
    /// Titles are server text encoded into the persisted `forumWatchedThreads` blob. Without a cap a
    /// hostile or MITM'd response could write unbounded text there, and because the unreadable-blob guard in `PersistedList`
    /// stops an undecodable blob from being overwritten, the bloat would stick. Same rule as the item
    /// catalog and typed watchlist names.
    nonisolated static func boundedTitle(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let cleaned = String(
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(WatchlistItem.maximumNameLength)
        )
        return cleaned.isEmpty ? nil : cleaned
    }

    nonisolated static func decodeThread(_ data: Data, _ json: [String: Any]) -> ForumThreadSnapshot? {
        let thread = json["thread"] as? [String: Any] ?? json
        // The post count is the whole point of this call, so a response without a usable one is malformed,
        // not a success with `postCount: 0`: a stored zero would make `apply`'s `previousCount > 0` guard
        // swallow the next real increase.
        let postCount: Int
        if let count = thread["posts"] as? Int {
            postCount = count
        } else if let text = thread["posts"] as? String, let count = Int(text) {
            postCount = count   // tolerate a stringified number
        } else {
            return nil
        }
        // Likewise, never overwrite a good title with a placeholder.
        let title = ForumWatchService.boundedTitle(thread["title"])
        return ForumThreadSnapshot(
                title: title ?? "Unknown",
                postCount: postCount
        )
    }
}
