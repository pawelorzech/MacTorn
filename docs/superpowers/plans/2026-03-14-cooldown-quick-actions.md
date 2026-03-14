# Cooldown Quick Action Buttons — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a cooldown reaches 0, turn the cooldown cell into a clickable button that opens the matching Torn Items page subsection.

**Architecture:** View-layer only changes. `CooldownItem` and `LiveCooldownItem` gain optional `actionURL`/`actionLabel` params. `StatusView` constructs URLs (reading booster preference from `@AppStorage`). `SettingsView` gets a new Picker for booster/alcohol target.

**Tech Stack:** SwiftUI, `@AppStorage`, `BrowserManager`

**Spec:** `docs/superpowers/specs/2026-03-14-cooldown-quick-actions-design.md`

---

## Chunk 1: Cooldown Views + Settings

### Task 1: Update `CooldownItem` with action button support

**Files:**
- Modify: `MacTorn/MacTorn/Views/StatusView.swift:267-296` (`CooldownItem`)

- [ ] **Step 1: Add new parameters and environment to `CooldownItem`**

Add `actionURL: URL?` and `actionLabel: String?` parameters (both defaulting to `nil`), and add `@Environment(\.reduceTransparency)`. Wrap the body in a conditional: if `seconds <= 0` and `actionURL` is non-nil, render as a `Button`; otherwise keep existing layout.

```swift
struct CooldownItem: View {
    let label: String
    let seconds: Int
    let icon: String
    var actionURL: URL? = nil
    var actionLabel: String? = nil

    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        if seconds <= 0, let url = actionURL {
            Button {
                BrowserManager.shared.open(url)
            } label: {
                cellContent(remaining: seconds)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(label)")
            .accessibilityHint("Opens Torn items page in browser")
        } else {
            cellContent(remaining: seconds)
        }
    }

    private func cellContent(remaining: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(remaining > 0 ? .orange : .green)

            Text(formattedTime)
                .font(.caption2.monospacedDigit())
                .foregroundColor(remaining > 0 ? .primary : .green)
                .fontWeight(remaining <= 0 ? .bold : .regular)

            if remaining <= 0, let actionLabel {
                Text(actionLabel)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, remaining <= 0 && actionURL != nil ? 4 : 0)
        .background(
            remaining <= 0 && actionURL != nil
                ? Color.green.opacity(reduceTransparency ? 0.25 : 0.12)
                : Color.clear
        )
        .overlay {
            if remaining <= 0 && actionURL != nil {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.green.opacity(reduceTransparency ? 0.4 : 0.25))
            }
        }
        .cornerRadius(6)
    }

    private var formattedTime: String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make build`
Expected: BUILD SUCCEEDED (existing call sites pass no `actionURL`/`actionLabel`, so defaults of `nil` keep them working)

- [ ] **Step 3: Commit**

```bash
git add MacTorn/MacTorn/Views/StatusView.swift
git commit -m "feat: add action button support to CooldownItem"
```

---

### Task 2: Update `LiveCooldownItem` with action button support

**Files:**
- Modify: `MacTorn/MacTorn/Views/StatusView.swift:299-334` (`LiveCooldownItem`)

- [ ] **Step 1: Add new parameters and environment to `LiveCooldownItem`**

Same pattern as `CooldownItem` — add `actionURL: URL?`, `actionLabel: String?`, and `@Environment(\.reduceTransparency)`. The `TimelineView` body wraps content in a conditional button when ready.

```swift
struct LiveCooldownItem: View {
    let label: String
    let originalSeconds: Int
    let fetchTime: Date
    let icon: String
    var actionURL: URL? = nil
    var actionLabel: String? = nil

    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.periodic(from: fetchTime, by: 1.0)) { context in
            let elapsed = Int(context.date.timeIntervalSince(fetchTime))
            let remaining = max(0, originalSeconds - elapsed)

            if remaining <= 0, let url = actionURL {
                Button {
                    BrowserManager.shared.open(url)
                } label: {
                    cellContent(remaining: remaining)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use \(label)")
                .accessibilityHint("Opens Torn items page in browser")
            } else {
                cellContent(remaining: remaining)
            }
        }
    }

    private func cellContent(remaining: Int) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(remaining > 0 ? .orange : .green)

            Text(formattedTime(remaining))
                .font(.caption2.monospacedDigit())
                .foregroundColor(remaining > 0 ? .primary : .green)
                .fontWeight(remaining <= 0 ? .bold : .regular)

            if remaining <= 0, let actionLabel {
                Text(actionLabel)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, remaining <= 0 && actionURL != nil ? 4 : 0)
        .background(
            remaining <= 0 && actionURL != nil
                ? Color.green.opacity(reduceTransparency ? 0.25 : 0.12)
                : Color.clear
        )
        .overlay {
            if remaining <= 0 && actionURL != nil {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.green.opacity(reduceTransparency ? 0.4 : 0.25))
            }
        }
        .cornerRadius(6)
    }

    private func formattedTime(_ seconds: Int) -> String {
        if seconds <= 0 { return "Ready" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add MacTorn/MacTorn/Views/StatusView.swift
git commit -m "feat: add action button support to LiveCooldownItem"
```

---

### Task 3: Wire up URLs in `cooldownsSection`

**Files:**
- Modify: `MacTorn/MacTorn/Views/StatusView.swift:3-5` (add `@AppStorage` property to `StatusView`)
- Modify: `MacTorn/MacTorn/Views/StatusView.swift:197-217` (`cooldownsSection`)

- [ ] **Step 1: Add `@AppStorage` property to `StatusView`**

Add after the existing `@Environment(\.reduceTransparency)` line:

```swift
@AppStorage("boosterCooldownTarget") private var boosterCooldownTarget: String = "boosters"
```

- [ ] **Step 2: Update `cooldownsSection` to pass URLs and labels**

```swift
private func cooldownsSection(_ cooldowns: Cooldowns) -> some View {
    let drugURL = URL(string: "https://www.torn.com/item.php#drugs-items")
    let medicalURL = URL(string: "https://www.torn.com/item.php#medical-items")
    let boosterURL = boosterCooldownTarget == "alcohol"
        ? URL(string: "https://www.torn.com/item.php#alcohol-items")
        : URL(string: "https://www.torn.com/item.php#boosters-items")
    let boosterLabel = boosterCooldownTarget == "alcohol" ? "Use Alcohol →" : "Use Booster →"

    return VStack(alignment: .leading, spacing: 8) {
        Divider()

        Text("Cooldowns")
            .font(.caption.bold())
            .foregroundColor(.secondary)

        HStack(spacing: 16) {
            if let fetchTime = appState.lastUpdated {
                LiveCooldownItem(label: "Drug", originalSeconds: cooldowns.drug, fetchTime: fetchTime, icon: "pills.fill", actionURL: drugURL, actionLabel: "Use Drug →")
                LiveCooldownItem(label: "Medical", originalSeconds: cooldowns.medical, fetchTime: fetchTime, icon: "cross.case.fill", actionURL: medicalURL, actionLabel: "Use Medical →")
                LiveCooldownItem(label: "Booster", originalSeconds: cooldowns.booster, fetchTime: fetchTime, icon: "arrow.up.circle.fill", actionURL: boosterURL, actionLabel: boosterLabel)
            } else {
                CooldownItem(label: "Drug", seconds: cooldowns.drug, icon: "pills.fill", actionURL: drugURL, actionLabel: "Use Drug →")
                CooldownItem(label: "Medical", seconds: cooldowns.medical, icon: "cross.case.fill", actionURL: medicalURL, actionLabel: "Use Medical →")
                CooldownItem(label: "Booster", seconds: cooldowns.booster, icon: "arrow.up.circle.fill", actionURL: boosterURL, actionLabel: boosterLabel)
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add MacTorn/MacTorn/Views/StatusView.swift
git commit -m "feat: wire cooldown action URLs in cooldownsSection"
```

---

### Task 4: Add booster target setting to `SettingsView`

**Files:**
- Modify: `MacTorn/MacTorn/Views/SettingsView.swift:6-7` (add `@AppStorage` property)
- Modify: `MacTorn/MacTorn/Views/SettingsView.swift:124-132` (add Picker after Reduce Transparency)

- [ ] **Step 1: Add `@AppStorage` property to `SettingsView`**

Add after the existing `@AppStorage("preferredBrowser")` line (line 7):

```swift
@AppStorage("boosterCooldownTarget") private var boosterCooldownTarget: String = "boosters"
```

- [ ] **Step 2: Add Picker after Reduce Transparency toggle**

Insert after the closing `}` of the Reduce Transparency HStack (after line 131), before the closing `}` of the settings VStack (line 132):

```swift
// Booster Cooldown Target
HStack {
    Image(systemName: "arrow.up.circle.fill")
        .foregroundColor(.secondary)
        .frame(width: 20)

    Picker("Booster cooldown link", selection: $boosterCooldownTarget) {
        Text("Boosters").tag("boosters")
        Text("Alcohol").tag("alcohol")
    }
    .pickerStyle(.segmented)
}
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add MacTorn/MacTorn/Views/SettingsView.swift
git commit -m "feat: add booster cooldown target setting"
```

---

### Task 5: Run all tests and verify

**Files:** None (verification only)

- [ ] **Step 1: Run unit tests**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make test`
Expected: All existing tests pass. No tests were broken since we only added optional parameters with defaults.

- [ ] **Step 2: Run UI tests**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make test-ui`
Expected: All existing UI tests pass.

- [ ] **Step 3: Build release to verify universal binary**

Run: `cd /Users/pawelorzech/Programowanie/MacTorn && make release`
Expected: BUILD SUCCEEDED for universal binary.
