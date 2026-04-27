import SwiftUI

struct ForumWatchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    @State private var showAddThread = false
    @State private var threadInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header
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
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation {
                            showAddThread.toggle()
                        }
                    } label: {
                        Image(systemName: showAddThread ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundColor(showAddThread ? .red : .green)
                    }
                    .buttonStyle(.plain)
                }

                // Add Thread Section
                if showAddThread {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thread URL or ID:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("forums.php...t=12345 or 12345", text: $threadInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onSubmit {
                                    addThread()
                                }

                            Button("Add") {
                                addThread()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(threadInput.isEmpty)
                        }
                    }
                    .padding(8)
                    .background(Color.gray.opacity(reduceTransparency ? 0.4 : 0.1))
                    .cornerRadius(6)
                }

                // Faction Forum Hint
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

                // Thread List
                if appState.watchedThreads.isEmpty && !showAddThread {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No threads watched")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Add forum threads to track new posts")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if !appState.watchedThreads.isEmpty {
                    ForEach(appState.watchedThreads) { thread in
                        ForumThreadRow(
                            thread: thread,
                            onOpen: {
                                openThread(thread.id)
                                appState.markThreadAsRead(thread.id)
                            },
                            onToggleNotifications: {
                                appState.toggleThreadNotifications(thread.id)
                            },
                            onRemove: {
                                appState.removeWatchedThread(thread.id)
                            }
                        )
                    }
                }

                Divider()

                // Quick Links
                HStack(spacing: 8) {
                    ActionButton(title: "Forums", icon: "bubble.left.fill", color: .blue) {
                        openURL("https://www.torn.com/forums.php")
                    }

                    if appState.factionData != nil {
                        ActionButton(title: "Faction Forum", icon: "person.3.fill", color: .orange) {
                            openURL("https://www.torn.com/forums.php#/p=forums&f=999&b=1&a=\(appState.factionData?.factionId ?? 0)")
                        }
                    }
                }
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func addThread() {
        guard !threadInput.isEmpty else { return }
        appState.addWatchedThread(input: threadInput)
        threadInput = ""
        withAnimation {
            showAddThread = false
        }
    }

    private func openThread(_ threadId: Int) {
        openURL("https://www.torn.com/forums.php#/p=threads&t=\(threadId)")
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
    }
}

// MARK: - Forum Thread Row
struct ForumThreadRow: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let thread: WatchedThread
    let onOpen: () -> Void
    let onToggleNotifications: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Faction badge
            if thread.isFactionThread {
                Image(systemName: "person.3.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Thread title (clickable)
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

            Spacer()

            // Error indicator
            if let error = thread.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .help(error)
            }

            // Last checked indicator
            if thread.lastChecked != nil && thread.error == nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .opacity(0.5)
            }

            // Notification toggle
            Button {
                onToggleNotifications()
            } label: {
                Image(systemName: thread.notificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.caption)
                    .foregroundColor(thread.notificationsEnabled ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help(thread.notificationsEnabled ? "Notifications on" : "Notifications off")

            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(reduceTransparency ? 0.3 : 0.05))
        .cornerRadius(4)
    }
}
