import Foundation
import Sentry
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "SentryManager")

/// Opt-in crash + error reporting via Sentry.
///
/// Off by default. User must enable explicitly via Settings or the post-update prompt.
/// All breadcrumbs and event URLs run through `tornRedactedURL` to strip the `key=`
/// query value before egress — Torn API keys must never leave the device.
enum SentryManager {
    static let enabledKey = "sentryEnabled"
    static let promptShownKey = "sentryPromptShownVersion"

    /// Public DSN — safe to embed in client builds (Sentry ingest endpoint, not a secret).
    private static let dsn = "https://2626521b9d106444bdc5b1d1e4b3b87b@o4511309952712704.ingest.de.sentry.io/4511309955792976"

    /// Tracks whether the SDK has been started in this process.
    private static var isStarted = false

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Call once at app launch. Starts the SDK only if the user has opted in.
    static func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    /// Apply current toggle state. Call after the user flips the Settings switch.
    static func applyState() {
        if isEnabled {
            start()
        } else if isStarted {
            SentrySDK.close()
            isStarted = false
        }
    }

    private static func start() {
        guard !isStarted else { return }
        isStarted = true

        let release = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        SentrySDK.start { options in
            options.dsn = dsn
            options.releaseName = "mactorn@\(release)"
            options.environment = Self.environment()

            // Crash + errors only — no perf, no profiling, no replays.
            options.tracesSampleRate = 0.0

            // PII hygiene: never send IP, device name, etc.
            options.sendDefaultPii = false

            // Strip API keys from URLs in events + breadcrumbs.
            options.beforeSend = { event in scrub(event) }
            options.beforeBreadcrumb = { crumb in scrub(crumb) }

            // Redact URLs Sentry might capture from URLSession swizzling.
            options.enableNetworkTracking = false
            options.enableNetworkBreadcrumbs = false
            // Torn API 5xx are upstream noise, not MacTorn bugs — don't auto-capture them.
            options.enableCaptureFailedRequests = false
        }
        logger.info("Sentry started, release \(release)")
    }

    private static func environment() -> String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    // MARK: - Scrubbing

    private static func scrub(_ event: Event) -> Event? {
        if let req = event.request, let urlString = req.url, let url = URL(string: urlString) {
            req.url = tornRedactedURL(url)
            req.queryString = nil
            event.request = req
        }
        // Also walk breadcrumbs already attached at send time.
        if let crumbs = event.breadcrumbs {
            event.breadcrumbs = crumbs.compactMap { scrub($0) }
        }
        return event
    }

    private static func scrub(_ crumb: Breadcrumb) -> Breadcrumb? {
        if var data = crumb.data {
            for key in ["url", "request", "to"] {
                if let raw = data[key] as? String, let url = URL(string: raw) {
                    data[key] = tornRedactedURL(url)
                }
            }
            crumb.data = data
        }
        if let msg = crumb.message, msg.contains("key=") {
            // Defensive: if a redacted URL slipped through, drop the message.
            crumb.message = "[redacted url]"
        }
        return crumb
    }
}
