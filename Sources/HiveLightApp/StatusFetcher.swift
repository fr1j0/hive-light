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
    @Published private(set) var components: [PlatformComponentStatus] = []

    private var fetching = false

    func refresh() {
        guard !fetching else { return }
        fetching = true
        // Drop the previous open's answer: a stale "major outage" (or a stale
        // all-clear) must never pose as current while the new fetch is in flight.
        components = []
        Task { [weak self] in
            let rows = await Task.detached(priority: .utility) { await Self.fetch() }.value
            self?.components = rows
            self?.fetching = false
        }
    }

    nonisolated static let pageURL = URL(string: "https://status.claude.com")!

    nonisolated static func fetch() async -> [PlatformComponentStatus] {
        var request = URLRequest(url: pageURL.appendingPathComponent("api/v2/components.json"))
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData   // "current" means current
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return platformStatus(fromJSON: data)
    }
}
