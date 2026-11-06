import Foundation
import Combine

extension AppState {
    @discardableResult
    func addWatchedThread(input: String) -> Bool {
        guard let threadId = forumWatch.add(input: input) else { return false }
        let identity = accountSession.identity
        Task {
            await checkThread(threadId)
            if accountSession.isCurrent(identity) { forumWatch.save() }
        }
        return true
    }

    func startForumPolling() {
        // A permanent key error holds until the key changes; the menu's onAppear must not
        // quietly restart the forum timer, nor restart one that polled recently.
        guard !keyHalted else { return }
        if forumTimerCancellable != nil,
           let last = lastForumFetchAt,
           Date().timeIntervalSince(last) < Double(forumWatchConfig.pollingIntervalSeconds) / 2 {
            return
        }
        forumTimerCancellable?.cancel()
        guard !apiKey.isEmpty else { return }
        refreshForumWatch()
        installForumTimer()
    }

    func installForumTimer() {
        let interval = Double(forumWatchConfig.pollingIntervalSeconds)
        forumTimerInterval = interval
        forumTimerCancellable = Timer.publish(every: interval, tolerance: interval / 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshForumWatch()
            }
    }

    func stopForumPolling() {
        forumTimerCancellable?.cancel()
        forumTimerCancellable = nil
        forumTimerInterval = nil
    }

    func refreshForumWatch() {
        accountSession.startTask(.forum) {
            await self.fetchForumUpdates()
        }
    }

    private func fetchForumUpdates() async {
        guard connectivity.isConnected, !apiKey.isEmpty, !keyHalted else { return }
        // Nothing to watch: no request, and no re-encoding two unchanged blobs every poll.
        guard !watchedThreads.isEmpty || forumWatchConfig.factionForumAutoMonitor else {
            lastForumFetchAt = Date()
            return
        }
        let identity = accountSession.identity
        await BoundedTaskQueue.run(watchedThreads.map(\.id), limit: 4) { [weak self] threadID in
            await self?.checkThread(threadID)
        }
        await checkFactionForumForNewThreads()
        guard !Task.isCancelled, accountSession.isCurrent(identity) else { return }
        lastForumFetchAt = Date()
        forumWatch.save()
    }

    /// Announces threads that appeared in the watched category since the last listing.
    private func checkFactionForumForNewThreads() async {
        guard forumWatchConfig.factionForumAutoMonitor,
              let categoryID = forumWatchConfig.factionForumCategoryId, categoryID > 0,
              let threads = await requester.fetch("forum.threads", parameter: categoryID,
                                                  decode: ForumWatchService.decodeCategoryThreads).value
        else { return }
        for thread in forumWatch.applyCategory(threads, for: categoryID) {
            notifier.send(title: "New forum thread", body: thread.title, type: .factionNewThread,
                          url: TornLink.forumThread(thread.id))
        }
    }

    /// Reads one thread's post count. A thread just added has no previous count, so its
    /// first read only records one and never announces.
    private func checkThread(_ threadID: Int) async {
        switch await requester.fetch("forum.thread", parameter: threadID, decode: ForumWatchService.decodeThread) {
        case .loaded(let snapshot):
            if let update = forumWatch.apply(snapshot, to: threadID) {
                notifier.send(title: "Forum: \(update.title)",
                              body: "\(update.count) new post\(update.count == 1 ? "" : "s")",
                              type: .forumNewPosts,
                              url: TornLink.forumThread(threadID))
            }
        case .failed(let failure):
            forumWatch.setError(failure.userMessage, for: threadID)
        case .skipped(let denial?):
            forumWatch.setError(denial.userExplanation, for: threadID)
        case .skipped(nil), .nothingToServe, .superseded:
            break
        }
    }
}
