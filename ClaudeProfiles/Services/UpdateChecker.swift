import Foundation
import Observation

/// Polls the GitHub Releases API for a newer published release of Claude Profiles
/// and surfaces a notice in the UI. The user installs manually by opening the
/// release page — we never download or replace the running bundle.
@MainActor
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(currentVersion: String)
        case updateAvailable(latestVersion: String, releaseURL: URL)
        case failed(message: String)
    }

    private(set) var state: State = .idle
    private(set) var lastCheckedAt: Date?

    /// Hard-coded to the public repo. Kept here rather than in a settings file because
    /// the launcher itself is the artifact being updated; pointing at a fork wouldn't
    /// help unless the user built that fork.
    static let repoOwner = "UpToSpeedDev"
    static let repoName = "ClaudeProfiles"

    private static let lastCheckedKey = "UpdateChecker.lastCheckedAt"
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
        if let stored = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date {
            self.lastCheckedAt = stored
        }
    }

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }

    /// Latest release URL if known; otherwise the repo's releases page.
    var releasesPageURL: URL {
        URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/latest")!
    }

    /// Kick off a background check if one hasn't run recently. Safe to call on every launch.
    func checkIfDue() {
        if let last = lastCheckedAt, Date().timeIntervalSince(last) < Self.autoCheckInterval {
            return
        }
        checkNow()
    }

    /// Force a fresh check regardless of the last-checked timestamp.
    func checkNow() {
        inFlight?.cancel()
        state = .checking
        inFlight = Task { [weak self] in
            guard let self else { return }
            await self.performCheck()
        }
    }

    private func performCheck() async {
        let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                finish(.failed(message: "No HTTP response"))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                finish(.failed(message: "GitHub returned HTTP \(http.statusCode)"))
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = Self.normalize(release.tagName)
            let current = Self.normalize(currentVersion)
            if Self.compare(latest, current) == .orderedDescending,
               let releaseURL = URL(string: release.htmlURL) {
                finish(.updateAvailable(latestVersion: latest, releaseURL: releaseURL))
            } else {
                finish(.upToDate(currentVersion: current))
            }
        } catch is CancellationError {
            // Superseded by a newer check — leave state alone.
        } catch {
            finish(.failed(message: error.localizedDescription))
        }
    }

    private func finish(_ newState: State) {
        state = newState
        let now = Date()
        lastCheckedAt = now
        UserDefaults.standard.set(now, forKey: Self.lastCheckedKey)
    }

    // MARK: - Version helpers

    /// Strip a leading "v" or "V" so "v1.2.3" and "1.2.3" compare the same way.
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" {
            s.removeFirst()
        }
        return s
    }

    /// Numeric component-wise comparison. Non-numeric suffixes (e.g. "1.0-beta")
    /// compare as 0, which is conservative — a tagged "1.0-beta" won't outrank
    /// a shipped "1.0".
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = components(lhs)
        let r = components(rhs)
        let count = max(l.count, r.count)
        for i in 0..<count {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            let digits = part.prefix(while: { $0.isNumber })
            return Int(digits) ?? 0
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
