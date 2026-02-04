import AppKit

enum PreferredBrowser: String, CaseIterable, Identifiable {
    case system = "System Default"
    case safari = "Safari"
    case chrome = "Google Chrome"
    case firefox = "Firefox"
    case edge = "Microsoft Edge"
    case brave = "Brave"

    var id: String { rawValue }

    var bundleIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .safari:
            return "com.apple.Safari"
        case .chrome:
            return "com.google.Chrome"
        case .firefox:
            return "org.mozilla.firefox"
        case .edge:
            return "com.microsoft.edgemac"
        case .brave:
            return "com.brave.Browser"
        }
    }

    init(storedValue: String?) {
        guard let storedValue,
              let value = PreferredBrowser(rawValue: storedValue) else {
            self = .system
            return
        }
        self = value
    }
}

final class BrowserManager {
    static let shared = BrowserManager()

    private init() {}

    func open(_ url: URL) {
        guard let scheme = url.scheme,
              ["http", "https"].contains(scheme) else {
            NSWorkspace.shared.open(url)
            return
        }

        let preference = PreferredBrowser(storedValue: UserDefaults.standard.string(forKey: "preferredBrowser"))
        guard let bundleIdentifier = preference.bundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration, completionHandler: nil)
    }
}
