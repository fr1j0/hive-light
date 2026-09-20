import Foundation
import Combine
import HiveLightCore

/// Fetches the Claude platform's current state from status.claude.com's
/// public Statuspage API — no login, no token, nothing sent. Deliberately
/// NOT polled: the fetch runs only when the Usage view opens ("if I suspect
/// something, I open the stats window and it fetches current status"), so
/// the panel makes no background calls for this. Silent fallback like the
/// plan limits: offline, timeout, or a reshaped response all yield no rows
/// and the section simply isn't drawn.
@MainActor
final class StatusFetcher: ObservableObject {
    @Published private(set) var headline: PlatformHeadline?
    @Published private(set) var components: [PlatformComponentStatus] = []

    private var fetching = false

    func refresh() {
        guard !fetching else { return }
        fetching = true
        // Drop the previous open's answer: a stale "major outage" (or a stale
        // all-clear) must never pose as current while the new fetch is in flight.
        headline = nil
        components = []
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { await Self.fetch() }.value
            self?.headline = result.headline
            self?.components = result.components
            self?.fetching = false
        }
    }

    nonisolated static let pageURL = URL(string: "https://status.claude.com")!

    /// One call: `summary.json` carries both the page's headline and the
    /// per-product components.
    nonisolated static func fetch() async -> (headline: PlatformHeadline?, components: [PlatformComponentStatus]) {
        var request = URLRequest(url: pageURL.appendingPathComponent("api/v2/summary.json"))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData   // "current" means current
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, []) }
        return (platformHeadline(fromJSON: data), platformStatus(fromJSON: data))
    }
}
