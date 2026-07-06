import Foundation
import UserNotifications
import HiveLightCore

/// Posts a native notification when a session flips to needs-you and focuses the
/// session's terminal when the user activates it. Fire-and-forget throughout:
/// denied authorization just means posts never land.
@MainActor
final class SessionNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// UNUserNotificationCenter traps without a real app bundle, so the whole
    /// feature is compiled out of reach for unbundled dev builds.
    static let available = Bundle.main.bundleIdentifier != nil

    /// Resolves a notification's session ID back to a live session at click time.
    var sessionLookup: ((String) -> Session?)?

    /// Install as delegate so clicks are handled and banners show while the
    /// (always-"active") menu-bar app is frontmost.
    func activate() {
        guard Self.available else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        guard Self.available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// One notification per session: the session ID as identifier makes a newer
    /// alert replace the previous one instead of stacking.
    func post(project: String, body: String, sessionID: String) {
        guard Self.available else { return }
        let content = UNMutableNotificationContent()
        content.title = project
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: sessionID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.identifier
        Task { @MainActor in
            if let session = self.sessionLookup?(sessionID) {
                TerminalFocuser.focus(session)
            }
            completionHandler()
        }
    }
}
