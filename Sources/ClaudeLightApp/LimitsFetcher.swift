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
    /// In-memory only, never persisted. Cached so the Keychain is touched once
    /// per app run — reading it on every fetch re-triggered the macOS consent
    /// prompt on every panel open. Cleared on 401 (Claude Code rotated the
    /// token) so the next cycle re-reads.
    private var cachedToken: String?
    nonisolated static let minInterval: TimeInterval = 300   // politeness toward an unofficial endpoint

    func refresh(force: Bool = false) {
        guard !fetching,
              force || Date().timeIntervalSince(lastFetch) >= Self.minInterval else { return }
        fetching = true
        let knownToken = cachedToken
        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                await Self.fetch(reusing: knownToken)
            }.value
            self?.cachedToken = outcome.token
            self?.limits = outcome.limits
            self?.fetching = false
            self?.lastFetch = Date()
        }
    }

    // MARK: - Off-main work (static: no self capture in the detached task)

    /// One fetch cycle: reuse the given token (or read the Keychain when nil),
    /// call the endpoint, and hand back the token worth keeping — nil on auth
    /// failure so the caller re-reads a possibly-rotated token next cycle.
    nonisolated static func fetch(reusing knownToken: String?) async -> (limits: [PlanLimit], token: String?) {
        guard let token = knownToken ?? keychainToken() else { return ([], nil) }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            return ([], token)   // offline etc. — keep the token, just no data
        }
        guard status == 200 else {
            // 401/403: token rotated or revoked — drop it so next cycle re-reads.
            let authFailed = status == 401 || status == 403
            return ([], authFailed ? nil : token)
        }
        return (planLimits(fromJSON: data), token)
    }

    /// Whether a Claude subscription (OAuth) login exists at all — attributes
    /// only, never the secret, so this NEVER triggers the Keychain consent
    /// prompt. API-key/Bedrock users have no such item; the plan-limits
    /// toggle disables itself for them instead of silently doing nothing.
    nonisolated static func oauthLoginPresent() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
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
