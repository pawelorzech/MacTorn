# Development

This guide covers building MacTorn from source and contributing to the project.

## Prerequisites

- **macOS 13.0+** (Ventura or later)
- **Xcode 15+** (with Swift 5)
- **Git**

## Getting the Source

```bash
git clone https://github.com/pawelorzech/MacTorn.git
cd MacTorn/MacTorn
```

## Building

### Using Xcode

```bash
open MacTorn.xcodeproj
```

Press `Cmd + R` to build and run.

### Using Make

MacTorn includes a Makefile for common operations:

```bash
# Build Debug version
make build

# Build Release (Universal Binary)
make release

# Run unit tests
make test

# Run UI tests
make test-ui

# Run all tests
make test-all

# Clean build artifacts
make clean
```

All make commands use `xcodebuild` with code signing disabled (`CODE_SIGN_IDENTITY="-"`).

## Project Structure

```
MacTorn/
├── MacTorn/                    # Main app target
│   ├── MacTornApp.swift        # App entry point
│   ├── ViewModels/
│   │   └── AppState.swift      # Central state manager
│   ├── Models/
│   │   └── TornModels.swift    # Data models & API config
│   ├── Views/
│   │   ├── ContentView.swift   # Main tab container
│   │   ├── StatusView.swift    # Status tab
│   │   ├── TravelView.swift    # Travel tab
│   │   ├── MoneyView.swift     # Money tab
│   │   ├── AttacksView.swift   # Attacks tab
│   │   ├── FactionView.swift   # Faction tab
│   │   ├── WatchlistView.swift # Watchlist tab
│   │   ├── SettingsView.swift  # Settings tab
│   │   └── Components/         # Reusable components
│   ├── Utilities/
│   │   ├── NotificationManager.swift
│   │   ├── LaunchAtLoginManager.swift
│   │   ├── ShortcutsManager.swift
│   │   └── SoundManager.swift
│   ├── Networking/
│   │   └── NetworkSession.swift # Network abstraction
│   └── Helpers/
│       └── TransparencyEnvironment.swift
├── MacTornTests/               # Unit tests
│   ├── Models/
│   ├── ViewModels/
│   ├── Mocks/
│   │   └── MockNetworkSession.swift
│   └── Fixtures/
│       └── TornAPIFixtures.swift
└── MacTornUITests/             # UI tests
```

## Architecture Overview

### App Structure

MacTorn uses SwiftUI with the `@main` attribute and `MenuBarExtra` scene for the menu bar interface.

### State Management

**AppState** (`AppState.swift`) is the central state manager:
- Uses `@MainActor` for thread safety
- Handles API polling via Combine's `Timer.publish`
- Manages data parsing, notifications, and watchlist
- Uses dependency injection via `NetworkSession` protocol

### Networking

The `NetworkSession` protocol abstracts network calls:

```swift
protocol NetworkSession {
    func data(from url: URL) async throws -> (Data, URLResponse)
}
```

This allows injecting `URLSession` for production and `MockNetworkSession` for testing.

### Data Models

All models are in `TornModels.swift`:
- `TornResponse` - Main API response
- `Bar` - Energy/Nerve/Happy/Life bar
- `Travel` - Travel status
- `Status` - Player status
- `Chain` - Faction chain
- `WatchlistItem` - Watched item with price

`TornAPI` enum contains endpoint configurations.

## Testing

### Writing Unit Tests

Tests use `MockNetworkSession` for API testing:

```swift
import XCTest
@testable import MacTorn

final class MyTests: XCTestCase {
    func testExample() async throws {
        let mockSession = MockNetworkSession()
        let appState = AppState(session: mockSession)

        try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)

        await appState.refreshNow()

        XCTAssertNotNil(appState.data)
    }
}
```

### Test Fixtures

`TornAPIFixtures.swift` contains sample JSON responses for testing.

### Running Tests

```bash
# Unit tests only
make test

# UI tests only
make test-ui

# All tests
make test-all
```

## Key Patterns

### API Polling

`AppState.startPolling()` uses Combine's Timer:

```swift
func startPolling() {
    timerCancellable?.cancel()
    timerCancellable = Timer.publish(every: TimeInterval(refreshInterval), on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            Task { @MainActor in
                await self?.fetchData()
            }
        }
}
```

### Live Countdown

Travel timer updates every second independently of API polling:

```swift
travelTimerCancellable = Timer.publish(every: 1, on: .main, in: .common)
    .autoconnect()
    .sink { [weak self] _ in
        self?.updateTravelCountdown()
    }
```

### Accessibility

`TransparencyEnvironment.swift` provides a custom environment key:

```swift
@Environment(\.reduceTransparency) private var reduceTransparency
```

Views use this to adjust backgrounds based on accessibility settings.

### State Persistence

- `@AppStorage` for simple values (API key, refresh interval, appearance)
- `UserDefaults` for complex data (notification rules, watchlist)

## Contributing

### Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make changes
4. Run tests (`make test-all`)
5. Commit with descriptive message
6. Push to your fork
7. Create a Pull Request

### Code Style

- Use Swift standard naming conventions
- Keep views focused and extract components
- Add tests for new functionality
- Update documentation as needed

### Pull Request Guidelines

- Describe what changes were made and why
- Reference any related issues
- Ensure all tests pass
- Keep changes focused (one feature/fix per PR)

## License

MacTorn is released under the MIT License. See [LICENSE](https://github.com/pawelorzech/MacTorn/blob/main/LICENSE) for details.

---

**See Also:** [[Changelog]] for version history
