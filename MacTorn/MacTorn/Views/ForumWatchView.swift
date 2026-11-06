import SwiftUI

struct ForumWatchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddThread = false
    @State private var threadInput = ""
    @State private var threadInputError: String?
    @State private var undo = UndoController<RemovedWatchedThread>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // With nothing watched there is nothing to fetch; the list's own empty
                // state explains that, so a "No data yet · Retry" strip would contradict it.
                if !appState.forumWatch.threads.isEmpty {
                    ModuleStateView(state: moduleState) {
                        appState.refreshForumWatch()
                    }
                }

                HStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(.blue)
                    Text("Forum Watch")
                        .font(.caption.bold())

                    Spacer()

                    Button {
                        appState.refreshForumWatch()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                            .frame(minWidth: 28, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh watched threads")

                    Button {
                        withAnimation(reduceMotion ? nil : .default) {
                            showAddThread.toggle()
                        }
                    } label: {
                        Image(systemName: showAddThread ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundColor(showAddThread ? .red : .green)
                            .frame(minWidth: 28, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showAddThread ? "Close add thread form" : "Add watched thread")
                }

                if showAddThread {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thread URL or ID:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("forums.php...t=12345 or 12345", text: $threadInput)
                                .accessibilityLabel("Thread URL or ID")
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onChange(of: threadInput) { _, _ in
                                    threadInputError = nil
                                }
                                .onSubmit {
                                    addThread()
                                }

                            Button("Add") {
                                addThread()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(threadInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let threadInputError {
                            Text(threadInputError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Thread input error: \(threadInputError)")
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(reduceTransparency ? 0.4 : 0.1))
                    .cornerRadius(6)
                }

                if appState.factionData != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        Text("Paste faction forum thread URLs above to watch them")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if appState.forumWatch.threads.isEmpty && !showAddThread {
                    EmptyStateView(icon: "bubble.left.and.exclamationmark.bubble.right",
                                   title: "No threads watched",
                                   subtitle: "Add forum threads to track new posts")
                } else if !appState.forumWatch.threads.isEmpty {
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

                PendingUndoBanner(controller: undo, message: { "\($0.thread.title) removed" }) {
                    undoRemoval()
                }

                Divider()

                HStack(spacing: 8) {
                    TileButton(title: "Forums", icon: "bubble.left.fill", color: .blue) {
                        openTorn(TornLink.forums)
                    }

                    if appState.factionData != nil {
                        TileButton(title: "Faction Forum", icon: "person.3.fill", color: .orange) {
                            openTorn(TornLink.page("forums.php#/p=forums&f=999&b=1&a=\(appState.factionData?.factionId ?? 0)"))
                        }
                    }
                }
            }
            .padding()
        }
        .onDisappear {
            undo.reset()
        }
    }

    private var moduleState: ModulePresentationState {
        appState.forumPresentationState
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
    @Environment(\.reduceTransparency) private var reduceTransparency
    let thread: WatchedThread
    let onOpen: () -> Void
    let onToggleNotifications: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if thread.isFactionThread {
                Image(systemName: "person.3.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .accessibilityLabel("Faction thread")
            }

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    onOpen()
                } label: {
                    Text(thread.title)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                if let error = thread.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if let error = thread.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .help(error)
                    .accessibilityLabel("Error: \(error)")
            }

            if thread.lastChecked != nil && thread.error == nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .opacity(0.5)
                    .accessibilityLabel("Last checked successfully")
            }

            Button {
                onToggleNotifications()
            } label: {
                Image(systemName: thread.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.caption)
                    .foregroundColor(thread.notificationsEnabled ? .blue : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(thread.notificationsEnabled ? "Notifications on" : "Notifications off")
            .accessibilityLabel(thread.notificationsEnabled
                                ? "Notifications on for \(thread.title). Disable notifications"
                                : "Notifications off for \(thread.title). Enable notifications")

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(thread.title) from watched threads")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(reduceTransparency ? 0.3 : 0.05))
        .cornerRadius(4)
    }
}
