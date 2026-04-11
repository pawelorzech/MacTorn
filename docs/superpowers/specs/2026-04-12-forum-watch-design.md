# Forum Watch Feature Design

## Context

MacTorn monitors Torn game data via the API and displays it in the macOS menu bar. Users have been requesting a way to track specific forum threads without keeping the browser open. Torn API v2 exposes full read-only forum endpoints (`/v2/forum/{threadId}/thread`, `/v2/forum/{categoryIds}/threads`). This feature adds the ability to watch forum threads for new posts and monitor the faction forum for new threads.

## Requirements

1. **Watch specific threads** - User pastes a forum URL or thread ID to add a thread to their watch list
2. **New post notifications** - Detect new posts via post-count diffing, notify user
3. **Bookmark mode** - Each thread can have notifications disabled (just a quick-access shortcut)
4. **Faction forum auto-monitoring** - Toggle to automatically detect new threads on the faction forum and notify
5. **Manual faction thread watching** - Ability to add specific faction threads to the watch list
6. **Separate polling** - Forum checks on independent 2-5 minute interval (not tied to main 30s poll)

## Design

### Data Models (TornModels.swift)

```swift
struct WatchedThread: Codable, Identifiable {
    let id: Int                     // threadId
    var title: String
    var notificationsEnabled: Bool  // false = bookmark only
    var lastKnownPostCount: Int
    var lastChecked: Date?
    var error: String?
    var isFactionThread: Bool       // true if auto-discovered from faction forum
}

struct ForumWatchConfig: Codable {
    var factionForumAutoMonitor: Bool   // toggle: monitor all faction threads
    var factionForumCategoryId: Int?    // cached faction forum category ID
    var pollingIntervalSeconds: Int     // 120-300, default 180
    var knownFactionThreadIds: Set<Int> // for detecting new threads
}
```

### API Endpoints (TornAPI)

Add to `TornAPI` enum:
- `forumThreadURL(threadId:apiKey:)` -> `https://api.torn.com/v2/forum/{threadId}/thread?key={apiKey}`
- `forumCategoryThreadsURL(categoryId:apiKey:)` -> `https://api.torn.com/v2/forum/{categoryId}/threads?key={apiKey}`

### Thread ID Parsing

Accept both formats:
- Full URL: regex `forums\.php.*[?&#]t=(\d+)` extracts thread ID
- Bare integer: parsed directly

### AppState Extensions (AppState.swift)

**New published state:**
- `@Published var watchedThreads: [WatchedThread] = []`
- `@Published var forumWatchConfig: ForumWatchConfig` (with defaults)

**New timer:**
- `forumTimerCancellable: AnyCancellable?`
- Separate Combine `Timer.publish` with interval from `forumWatchConfig.pollingIntervalSeconds`

**Methods:**
- `addWatchedThread(input: String)` - Parse URL or ID, fetch thread metadata, add to list
- `removeWatchedThread(_ threadId: Int)` - Remove from list, save
- `toggleThreadNotifications(_ threadId: Int)` - Toggle `notificationsEnabled`
- `loadForumWatch() / saveForumWatch()` - UserDefaults persistence (keys: `"forumWatchedThreads"`, `"forumWatchConfig"`)
- `startForumPolling() / stopForumPolling()` - Manage forum timer
- `fetchForumUpdates()` - Main poll function:
  1. TaskGroup: fetch each watched thread's metadata via `/v2/forum/{threadId}/thread`
  2. Compare `response.posts` vs `lastKnownPostCount`
  3. If increased and `notificationsEnabled`: fire notification
  4. Update `lastKnownPostCount` and `lastChecked`
- `fetchFactionForumUpdates()` - Called if `factionForumAutoMonitor` is on:
  1. Fetch `/v2/forum/{factionCategoryId}/threads`
  2. Compare thread IDs against `knownFactionThreadIds`
  3. New threads: notify and auto-add to `watchedThreads` with `isFactionThread = true`
  4. Update `knownFactionThreadIds`
- `markThreadAsRead(_ threadId: Int)` - Set `lastKnownPostCount` to current count (called on click-through)

### Faction Forum Category Discovery

When user enables faction auto-monitor:
1. Use faction ID from existing `factionData?.factionId`
2. Torn faction forum category ID often matches faction ID - call `/v2/forum/{factionId}/threads` to verify
3. If works, cache `factionForumCategoryId`. If not, fall back to scanning `/v2/forum/categories` for the faction name

### Notifications (NotificationManager.swift)

Add to `NotificationType`:
- `.forumNewPosts` -> URL: `https://www.torn.com/forums.php#/p=threads&t={threadId}`
- `.factionNewThread` -> URL: same pattern

Notification content examples:
- "3 new posts in 'Faction War Plans'"
- "New faction forum thread: 'Important Announcement'"

### New Tab (ContentView.swift)

Add `case forums = "Forums"` to `AppTab` enum with icon `"bubble.left.and.bubble.right.fill"`.

### View (new file: ForumWatchView.swift)

Structure following WatchlistView pattern:

```
Header: title + refresh button
Add Section: TextField (URL or ID) + Add button
Faction Section: Toggle "Monitor faction forum"
Thread List: ForEach over watchedThreads
  ForumThreadRow:
    - Thread title (clickable -> opens browser, marks as read)
    - Badge: "X new" posts (if any)
    - Bell toggle: notifications on/off
    - Remove button (swipe or X)
```

### Settings (SettingsView.swift)

Add forum polling interval picker (120s / 180s / 300s) in settings, following existing HStack { Image + Picker } pattern.

### Persistence

- `UserDefaults` key `"forumWatchedThreads"` -> `[WatchedThread]` via JSONEncoder
- `UserDefaults` key `"forumWatchConfig"` -> `ForumWatchConfig` via JSONEncoder
- Load in `AppState.init()`, save after every mutation

### "Mark as Read" Behavior

- Clicking a thread title opens it in the browser AND resets `lastKnownPostCount` to current value
- Badge "X new" clears immediately on click
- Next poll will only show posts that arrived after the click

## Files to Modify

| File | Changes |
|------|---------|
| `Models/TornModels.swift` | Add `WatchedThread`, `ForumWatchConfig` models; extend `TornAPI` with forum URL builders |
| `ViewModels/AppState.swift` | Add forum watch state, timer, polling, add/remove/notification methods |
| `Views/ContentView.swift` | Add `.forums` to `AppTab` enum, wire up `ForumWatchView` |
| `Views/ForumWatchView.swift` | **New file** - Forum watch tab view |
| `Utilities/NotificationManager.swift` | Add `.forumNewPosts` and `.factionNewThread` notification types |
| `Views/SettingsView.swift` | Add forum polling interval picker |

## Files to Add (Tests)

| File | Purpose |
|------|---------|
| `MacTornTests/Models/WatchedThreadTests.swift` | Model encoding/decoding, backward compat |
| `MacTornTests/ViewModels/AppStateForumWatchTests.swift` | Add/remove, persistence, notification triggering |
| `MacTornTests/Fixtures/TornAPIFixtures.swift` | Add forum thread + faction threads JSON fixtures |

## Verification

1. **Build**: `make build` succeeds
2. **Tests**: `make test` passes with new test files
3. **Manual testing**:
   - Add thread by URL -> appears in list with title
   - Add thread by ID -> same result
   - Wait for poll -> "X new" badge updates
   - Click thread -> opens in browser, badge clears
   - Toggle notification bell -> no notification on next poll
   - Enable faction monitor -> detects new faction threads
   - Change polling interval in settings -> timer updates
4. **Edge cases**:
   - Invalid URL/ID -> error message shown
   - Duplicate thread -> prevented
   - Network error -> error state on thread, retry on next poll
   - No API key -> forum polling doesn't start
