import SwiftUI

/// Watched forum threads: each with its post count up front, when it was last checked, and
/// the notification switch and remove action kept quiet.
struct ForumWatchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddThread = false
    @State private var threadInput = ""
    @State private var threadInputError: String?
    @State private var undo = UndoController<RemovedWatchedThread>()

    var body: some View {
        BoardPage {
            // With nothing watched there is nothing to fetch; the list's own empty
            // state explains that, so a "No data yet, Retry" strip would contradict it.
            if !appState.forumWatch.threads.isEmpty {
                ModuleStateView(state: moduleState) {
                    appState.refreshForumWatch()
                }
            }

            BoardSection(title: "Watched threads", trailing: {
                HStack(spacing: 0) {
                    IconButton(systemImage: "arrow.clockwise", label: "Refresh watched threads") {
                        appState.refreshForumWatch()
                    }
                    IconButton(
                        systemImage: showAddThread ? "minus" : "plus",
                        label: showAddThread ? "Close add thread form" : "Add watched thread"
                    ) {
                        withAnimation(reduceMotion ? nil : .default) {
                            showAddThread.toggle()
                        }
                    }
                }
            }) {
                if showAddThread {
                    addPanel
                }

                if appState.forumWatch.threads.isEmpty && !showAddThread {
                    BoardEmptyState(
                        title: "No threads watched",
                        detail: "Use the plus button to add a thread and hear about new posts."
                    )
                } else {
                    ForEach(appState.forumWatch.threads) { thread in
                        ForumThreadRow(
                            thread: thread,
                            onOpen: {
                                openThread(thread.id)
                                appState.forumWatch.markAsRead(threadID: thread.id)
                            },
                            onToggleNotifications: {
                                appState.forumWatch.toggleNotifications(threadID: thread.id)
                            },
                            onRemove: {
                                removeWithUndo(thread)
                            }
                        )
                    }
                }
            }

            if appState.factionData != nil {
                Text("Paste a faction forum thread URL to watch it.")
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
            }

            PendingUndoBanner(controller: undo, message: { "\($0.thread.title) removed" }) {
                undoRemoval()
            }

            BoardSection("Open in Torn") {
                TornLinks(links: tornLinks, columns: tornLinks.count)
                    .padding(.top, Board.Space.s)
            }
        }
        .onDisappear {
            undo.reset()
        }
    }

    // MARK: - Add thread

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: Board.Space.s) {
            HStack(spacing: 6) {
                TextField("Thread URL or ID", text: $threadInput)
                    .accessibilityLabel("Thread URL or ID")
                    .textFieldStyle(.board)
                    .onChange(of: threadInput) { _, _ in
                        threadInputError = nil
                    }
                    .onSubmit {
                        addThread()
                    }

                Button("Add") {
                    addThread()
                }
                .buttonStyle(.boardPrimary)
                .disabled(threadInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let threadInputError {
                BoardNotice(tone: .alert, message: threadInputError)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Thread input error: \(threadInputError)")
            } else {
                Text("A forum link or the number after t= in it, like forums.php…t=12345 or 12345.")
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Board.Space.s)
        .padding(.bottom, Board.Space.m)
        .overlay(alignment: .bottom) {
            Board.hairline.frame(height: 1)
        }
    }

    private var moduleState: ModulePresentationState {
        appState.forumPresentationState
    }

    private var tornLinks: [TornLinks.Link] {
        var links = [TornLinks.Link(title: "Forums", url: TornLink.forums)]
        if appState.factionData != nil {
            links.append(TornLinks.Link(
                title: "Faction forum",
                url: TornLink.page("forums.php#/p=forums&f=999&b=1&a=\(appState.factionData?.factionId ?? 0)")
            ))
        }
        return links
    }

    private func addThread() {
        guard appState.forumWatch.parseThreadInput(threadInput) != nil else {
            threadInputError = "Enter a positive thread ID or Torn forum URL."
            return
        }
        guard appState.addWatchedThread(input: threadInput) else {
            threadInputError = "This thread is already being watched."
            return
        }
        threadInput = ""
        threadInputError = nil
        withAnimation(reduceMotion ? nil : .default) {
            showAddThread = false
        }
    }

    private func openThread(_ threadId: Int) {
        openTorn(TornLink.forumThread(threadId))
    }

    private func removeWithUndo(_ thread: WatchedThread) {
        guard let index = appState.forumWatch.threads.firstIndex(where: { $0.id == thread.id }) else {
            return
        }
        let removedThread = appState.forumWatch.threads[index]

        undo.schedule(RemovedWatchedThread(thread: removedThread, index: index), reduceMotion: reduceMotion) {
            appState.forumWatch.remove(threadID: thread.id)
        }
    }

    private func undoRemoval() {
        undo.undo(reduceMotion: reduceMotion) { removed in
            appState.forumWatch.restore(removed.thread, at: removed.index)
        }
    }
}

private struct RemovedWatchedThread {
    let thread: WatchedThread
    let index: Int
}

// MARK: - Forum Thread Row

struct ForumThreadRow: View {
    let thread: WatchedThread
    let onOpen: () -> Void
    let onToggleNotifications: () -> Void
    let onRemove: () -> Void

    var body: some View {
        BoardRow {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: Board.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        titleButton
                        checkedLine
                    }

                    Spacer(minLength: Board.Space.s)

                    postCount

                    HStack(spacing: 0) {
                        IconButton(
                            systemImage: thread.notificationsEnabled ? "bell.fill" : "bell.slash",
                            label: thread.notificationsEnabled
                                ? "Notifications on for \(thread.title). Disable notifications"
                                : "Notifications off for \(thread.title). Enable notifications",
                            action: onToggleNotifications
                        )
                        IconButton(
                            systemImage: "xmark",
                            label: "Remove \(thread.title) from watched threads",
                            action: onRemove
                        )
                    }
                }

                if let error = thread.error {
                    BoardNotice(tone: .alert, message: error)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private var titleButton: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 5) {
                if thread.isFactionThread {
                    Image(systemName: "person.3.fill")
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                        .accessibilityLabel("Faction thread")
                }
                Text(thread.title)
                    .font(.boardStrong)
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// When the thread was last read, or that it could not be. The symbol carries the
    /// state next to the words, with its own label for VoiceOver.
    @ViewBuilder
    private var checkedLine: some View {
        if let error = thread.error {
            // The notice under the row carries the reason in words; this keeps the
            // symbol (and its VoiceOver label) next to the timing.
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Board.Tone.alert.ink)
                    .accessibilityLabel("Error: \(error)")
                if let checked = thread.lastChecked {
                    (Text("Last read ") + Text(checked, style: .relative) + Text(" ago"))
                        .foregroundStyle(Board.inkSecondary)
                } else {
                    Text("Not read yet")
                        .foregroundStyle(Board.inkSecondary)
                }
            }
            .font(.boardDetail)
            .lineLimit(1)
            .help(error)
        } else if let checked = thread.lastChecked {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Board.Tone.ready.ink)
                    .accessibilityLabel("Last checked successfully")
                (Text("Checked ") + Text(checked, style: .relative) + Text(" ago"))
                    .foregroundStyle(Board.inkSecondary)
            }
            .font(.boardDetail)
        } else {
            Text("Not checked yet")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
        }
    }

    private var postCount: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(thread.lastKnownPostCount > 0 ? thread.lastKnownPostCount.formatted() : "-")
                .font(.figureValue)
                .foregroundStyle(Board.ink)
                .lineLimit(1)
            Text(thread.lastKnownPostCount == 1 ? "post" : "posts")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thread.lastKnownPostCount > 0
                            ? "\(thread.lastKnownPostCount) posts"
                            : "Post count unknown")
    }
}
