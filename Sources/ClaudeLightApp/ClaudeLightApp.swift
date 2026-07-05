import SwiftUI
import AppKit
import ClaudeLightCore

@main
struct ClaudeLightApp: App {
    init() {
        // AppKit's ~2s default hover delay makes the tick gauge's tooltip
        // feel broken — by the time it fires the cursor has moved on.
        // register(defaults:) still respects an explicit user override.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
    }

    @StateObject private var watcher: SessionWatcher = {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Points at the bundled hook binary inside the running .app.
        let hookPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/claude-light-hook").path
        let installer = HookInstaller(settingsURL: settings, command: shellQuoted(hookPath))
        return SessionWatcher(
            store: SessionStore(directory: SessionStore.defaultDirectory()),
            installer: installer
        )
    }()

    var body: some Scene {
        MenuBarExtra {
            PanelContent(watcher: watcher)
        } label: {
            Image(nsImage: TrafficLightIcon.image(
                state: watcher.icon,
                phase: watcher.animationPhase,
                mono: watcher.isDarkMenuBar ? .white : .black))
                .onAppear {
                    watcher.start()
                    DispatchQueue.main.async { offerHookInstallIfNeeded() }
                }
        }
        .menuBarExtraStyle(.window)
    }

    /// On the very first launch, if the hooks aren't installed yet, greet the
    /// user once and offer to install them. Records that we asked so it never
    /// nags again — the menu's Install action remains the fallback.
    private func offerHookInstallIfNeeded() {
        let askedKey = "didOfferHookInstall"
        let defaults = UserDefaults.standard
        guard !watcher.hooksInstalled, !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Welcome to Claude Light"
        alert.informativeText = """
        Claude Light shows a menu-bar light for your Claude Code sessions: \
        orange while an agent is working, red when one needs your input, and \
        green when it's idle.

        To do that, it adds a small hook to your Claude Code settings \
        (~/.claude/settings.json). You can remove it anytime from the menu.
        """
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            watcher.installHooks()
        }
    }

}
