import Foundation
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "UpdateManager")

// MARK: - Update Manager
struct GitHubRelease: Codable {
    let tagName: String
    let htmlUrl: String
    let body: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case body
    }
}

class UpdateManager {
    // Configure your repository here
    private let githubOwner = "pawelorzech"
    private let githubRepo = "MacTorn"

    /// GitHub's API, not Torn's — bypassing the Torn budget-gated `session` on
    /// `AppState` is correct here. The bug was that this was hard-coded to
    /// `URLSession.shared`, so the type had 0% test coverage; injecting it lets tests
    /// substitute a `MockNetworkSession` (issue #56).
    private let session: NetworkSession

    init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }

    /// Hosts a release link may point at.
    ///
    /// `GitHubRelease.htmlUrl` is decoded straight from api.github.com and handed to
    /// `BrowserManager` behind a button labelled "Download Update". `BrowserManager`
    /// checks the scheme, which stops `NSWorkspace` opening arbitrary handlers, but any
    /// https host still passes — so a compromised or MITM'd GitHub response could send the
    /// user somewhere else entirely under MacTorn's own update prompt.
    static let allowedReleaseHosts: Set<String> = ["github.com", "www.github.com"]

    /// Whether a release's link points somewhere MacTorn is willing to send the user.
    static func isTrustedReleaseURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return allowedReleaseHosts.contains(host)
    }

    func checkForUpdates(currentVersion: String) async -> GitHubRelease? {
        let urlString = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            // Compare versions. Strip only a LEADING "v" prefix — release tags can
            // legitimately contain other "v" characters (e.g. "v1.2.3-victory"), and
            // `replacingOccurrences(of: "v", with: "")` used to strip every one of
            // them, mangling the version string past the parseable components.
            let versionString = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName

            if isVersion(versionString, greaterThan: currentVersion) {
                return release
            }

        } catch {
            logger.warning("Update check failed: \(error.localizedDescription)")
        }

        return nil
    }
    
    /// The leading run of digits in a dot-separated component, e.g. "3-victory" -> 3.
    /// A component that starts with a non-digit (or is empty) contributes 0 rather
    /// than being dropped, so a trailing suffix (build metadata, a named release)
    /// can't shift later components out of alignment.
    private func leadingNumericPrefix(_ component: Substring) -> Int {
        Int(component.prefix { $0.isNumber }) ?? 0
    }

    private func isVersion(_ newVersion: String, greaterThan currentVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").map(leadingNumericPrefix)
        let currentComponents = currentVersion.split(separator: ".").map(leadingNumericPrefix)

        let maxLength = max(newComponents.count, currentComponents.count)
        
        for i in 0..<maxLength {
            let new = i < newComponents.count ? newComponents[i] : 0
            let current = i < currentComponents.count ? currentComponents[i] : 0
            
            if new > current {
                return true
            } else if new < current {
                return false
            }
        }
        
        return false
    }
}
