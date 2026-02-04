import AppKit

enum PreferredBrowser: String, CaseIterable, Identifiable {
    case system = "System Default"
    case safari = "Safari"
    case chrome = "Google Chrome"
    case firefox = "Firefox"
    case edge = "Microsoft Edge"
    case brave = "Brave"
    case arc = "Arc"
    case vivaldi = "Vivaldi"
    case zen = "Zen"
    case opera = "Opera"
    case duckduckgo = "DuckDuckGo"
    case orion = "Orion"
    case tor = "Tor Browser"
    case chromium = "Chromium"
    case librewolf = "LibreWolf"
    case waterfox = "Waterfox"
    case atlas = "ChatGPT Atlas"

    var id: String { rawValue }

    var bundleIdentifiers: [String]? {
        switch self {
        case .system:
            return nil
        case .safari:
            return ["com.apple.Safari"]
        case .chrome:
            return ["com.google.Chrome"]
        case .firefox:
            return ["org.mozilla.firefox"]
        case .edge:
            return ["com.microsoft.edgemac"]
        case .brave:
            return ["com.brave.Browser"]
        case .arc:
            return ["company.thebrowser.Browser"]
        case .vivaldi:
            return ["com.vivaldi.Vivaldi"]
        case .zen:
            return ["app.zen-browser.zen"]
        case .opera:
            return ["com.operasoftware.Opera"]
        case .duckduckgo:
            return ["com.duckduckgo.macos.browser"]
        case .orion:
            return ["com.kagi.kagimacOS", "com.kagi.kagimacOS.RC"]
        case .tor:
            return ["com.torproject.tor"]
        case .chromium:
            return ["org.chromium.Chromium"]
        case .librewolf:
            return ["io.gitlab.librewolf-community"]
        case .waterfox:
            return ["net.waterfox.waterfox"]
        case .atlas:
            return ["com.openai.atlas"]
        }
    }

    var installedApplicationURL: URL? {
        guard let bundleIdentifiers else { return nil }
        for bundleIdentifier in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return appURL
            }
        }
        return nil
    }

    var isInstalled: Bool {
        self == .system || installedApplicationURL != nil
    }

    static func availableBrowsers() -> [PreferredBrowser] {
        PreferredBrowser.allCases.filter { $0.isInstalled }
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
        guard let appURL = preference.installedApplicationURL else {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration, completionHandler: nil)
    }
}
