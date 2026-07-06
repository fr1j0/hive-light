import Foundation
import Combine
import Security
import ClaudeLightCore

/// Fetches the account's real plan-limit levels (#83) from Anthropic's OAuth
/// usage endpoint — the same read `/usage` performs. Strictly additive with
/// silent fallback: no Keychain item, denied access, 401, offline, or a
/// reshaped response all yield empty limits and hide the section; never an
/// error state. The token is read from the Keychain item Claude Code itself
/// maintains, used once in an Authorization header, and never logged,
/// persisted, or sent anywhere else.
@MainActor
final class LimitsFetcher: ObservableObject {
    @Published private(set) var limits: [PlanLimit] = []

    private var fetching = false
    private var lastFetch = Date.distantPast
    nonisolated static let minInterval: TimeInterval = 300   // politeness toward an unofficial endpoint

    func refresh(force: Bool = false) {
        guard !fetching,
              force || Date().timeIntervalSince(lastFetch) >= Self.minInterval else { return }
        fetching = true
        Task { [weak self] in
            let fetched = await Task.detached(priority: .utility) {
                await Self.fetch()
            }.value
            self?.limits = fetched
            self?.fetching = false
            self?.lastFetch = Date()
        }
    }

    // MARK: - Off-main work (static: no self capture in the detached task)

    nonisolated static func fetch() async -> [PlanLimit] {
        guard let token = keychainToken() else { return [] }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return planLimits(fromJSON: data)
    }

    /// Claude Code stores its OAuth credentials at login; we only read them.
    /// First read triggers macOS's one-time permission prompt — deny is a
    /// supported answer (empty limits).
    nonisolated static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }
}
