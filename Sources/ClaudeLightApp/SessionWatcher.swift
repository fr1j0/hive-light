import Foundation
import Combine
import CoreServices
import AppKit
import ServiceManagement
import ClaudeLightCore

@MainActor
final class SessionWatcher: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var hooksInstalled: Bool = false
    @Published private(set) var errorReasons: [String: String] = [:]
    /// Why the last install/remove-hooks click failed; nil after a success.
    @Published private(set) var hookActionError: String? = nil
    @Published private(set) var icon: IconState = IconState(red: .off, orange: .off, green: .off)
    @Published private(set) var summary: String? = nil
    @Published private(set) var animationPhase: Double = 0
    @Published private(set) var isDarkMenuBar: Bool = true
    @Published private(set) var subagentsBySession: [String: SubagentList] = [:]
    /// Opt-in: show a running session's parallel subagents as indented rows.
    @Published var showSubagents: Bool {
        didSet {
            UserDefaults.standard.set(showSubagents, forKey: Self.showSubagentsKey)
            reload()
        }
    }
    @Published var showUsageStats: Bool {
        didSet {
            UserDefaults.standard.set(showUsageStats, forKey: Self.showUsageStatsKey)
        }
    }
    @Published var showPlanLimits: Bool {
        didSet {
            UserDefaults.standard.set(showPlanLimits, forKey: Self.showPlanLimitsKey)
        }
    }
    /// Panel row order (stable-session-order spec): grouped by repo (default)
    /// or pure open-order. Re-sorts immediately on change.
    @Published var sessionOrder: SessionOrder {
        didSet {
            UserDefaults.standard.set(sessionOrder.rawValue, forKey: Self.sessionOrderKey)
            reload()
        }
    }
    @Published private(set) var launchAtLoginEnabled: Bool = false

    /// SMAppService needs a real .app bundle; unbundled dev builds hide the row.
    let launchAtLoginAvailable = Bundle.main.bundleIdentifier != nil

    /// Opt-in: post a native notification when a session flips to needs-you.
    @Published var notifyOnNeedsYou: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnNeedsYou, forKey: Self.notifyKey)
            if notifyOnNeedsYou { notifier.requestAuthorization() }
        }
    }
    var notificationsAvailable: Bool { SessionNotifier.available }

    private static let showSubagentsKey = "showSubagents"
    private static let showUsageStatsKey = "showUsageStats"
    private static let showPlanLimitsKey = "showPlanLimits"
    private static let sessionOrderKey = "sessionOrder"
    private static let notifyKey = "notifyOnNeedsYou"
    private let notifier = SessionNotifier()
    /// Previous reload's statuses; nil until the first reload has taken a
    /// baseline, so launching never replays already-red sessions.
    private var lastStatuses: [String: SessionStatus]? = nil
    private let subagentCache = FileMemoCache<SubagentList>()
    private let store: SessionStore
    private let installer: HookInstaller
    private var stream: FSEventStreamRef?
    private var staleTimer: Timer?
    private var clockTimer: Timer?
    private var started = false
    private let clockInterval: TimeInterval = 0.08

    init(store: SessionStore, installer: HookInstaller) {
        self.store = store
        self.installer = installer
        self.showSubagents = UserDefaults.standard.bool(forKey: Self.showSubagentsKey)
        self.showUsageStats = UserDefaults.standard.bool(forKey: Self.showUsageStatsKey)
        self.showPlanLimits = UserDefaults.standard.bool(forKey: Self.showPlanLimitsKey)
        self.sessionOrder = UserDefaults.standard.string(forKey: Self.sessionOrderKey)
            .flatMap(SessionOrder.init(rawValue:)) ?? .project
        self.notifyOnNeedsYou = UserDefaults.standard.bool(forKey: Self.notifyKey)
    }

    /// Call exactly once. Idempotent: subsequent calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        hooksInstalled = installer.isInstalled()
        refreshLaunchAtLogin()
        notifier.activate()
        notifier.sessionLookup = { [weak self] id in
            self?.sessions.first { $0.sessionID == id }
        }
        if notifyOnNeedsYou { notifier.requestAuthorization() }
        updateAppearance()
        observeAppearance()
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        store.prune(now: Date())
        reload()
        startFSEvents()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.store.prune(now: Date())
                self.refreshLaunchAtLogin()   // tracks changes made in System Settings
                self.reload()
            }
        }
    }

    func toggleLaunchAtLogin() {
        guard launchAtLoginAvailable else { return }
        // Failures (e.g. user denied in System Settings) surface via the re-read:
        // the checkbox simply stays where the system says it is.
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        guard launchAtLoginAvailable else { return }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func installHooks() {
        do {
            try installer.install()
            hookActionError = nil
        } catch {
            hookActionError = Self.hookActionErrorMessage(for: error)
        }
        hooksInstalled = installer.isInstalled()
    }

    func removeHooks() {
        do {
            try installer.uninstall()
            hookActionError = nil
        } catch {
            hookActionError = Self.hookActionErrorMessage(for: error)
        }
        hooksInstalled = installer.isInstalled()
    }

    private static func hookActionErrorMessage(for error: Error) -> String {
        if case HookInstallerError.unparseableSettings = error {
            return "settings.json couldn't be parsed — fix it and retry"
        }
        return "couldn't update settings.json"
    }

    func reload() {
        let all = (try? store.loadAll()) ?? []
        var live = liveSessions(all, now: Date())
        var reasons: [String: String] = [:]
        var subagentMap: [String: SubagentList] = [:]
        var scannedTranscripts: Set<String> = []
        for i in live.indices where live[i].status == .running {
            guard let path = live[i].transcriptPath else { continue }
            if let tail = transcriptTail(path: path),
               let reason = apiErrorReason(transcriptJSONL: tail) {
                live[i].status = .error
                reasons[live[i].sessionID] = reason
                continue                                  // errored → not a running subagent host
            }
            if showSubagents, let stamp = fileStamp(path: path) {
                // The wide tail read is expensive (up to 4 MB per reload); memoize
                // the parsed list until the transcript's (mtime, size) changes.
                let list = subagentCache.value(for: path, stamp: stamp) { [weak self] in
                    guard let wide = self?.transcriptTail(path: path, maxBytes: 4 * 1024 * 1024)
                    else { return .empty }
                    return subagents(fromTranscript: wide)
                }
                if !list.isEmpty { subagentMap[live[i].sessionID] = list }
                scannedTranscripts.insert(path)
            }
        }
        subagentCache.evict(keeping: scannedTranscripts)
        // Idle headless runs (plugin jobs, claude -p) are noise: dropped from
        // the rows AND the counts/light so they can't hold the menu hostage.
        let sorted = sortedForMenu(visibleSessions(live), order: sessionOrder)
        // Post-error-detection so running→error transitions count; the first
        // reload only takes the baseline. The snapshot updates even while the
        // toggle is off, so enabling it never replays old transitions.
        if let previous = lastStatuses, notifyOnNeedsYou {
            for session in newlyNeedingYou(previous: previous, current: sorted) {
                let body = cardSubtitle(for: session, errorReason: reasons[session.sessionID])
                    ?? friendlyStatusLabel(for: session.status)
                notifier.post(project: displayName(for: session), body: body, sessionID: session.sessionID)
            }
        }
        lastStatuses = Dictionary(sorted.map { ($0.sessionID, $0.status) },
                                  uniquingKeysWith: { a, _ in a })
        self.sessions = sorted
        self.errorReasons = reasons
        self.subagentsBySession = subagentMap
        let state = iconState(for: sorted)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: sorted))
        updateClock(animating: state.isAnimating)
    }

    /// The file's (mtime, size) identity, or nil if it can't be stat'ed.
    private func fileStamp(path: String) -> FileStamp? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = (attrs[.size] as? NSNumber)?.uint64Value else { return nil }
        return FileStamp(mtime: mtime, size: size)
    }

    /// Reads the last `maxBytes` of a transcript file (whole file if smaller).
    /// Fail-safe: returns nil on any error. A partial first line is fine —
    /// `apiErrorReason` scans bottom-up and skips unparseable lines.
    private func transcriptTail(path: String, maxBytes: Int = 64 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs the animation clock only while a lamp is blinking or breathing.
    private func updateClock(animating: Bool) {
        if animating {
            guard clockTimer == nil else { return }
            clockTimer = Timer.scheduledTimer(withTimeInterval: clockInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.animationPhase += self.clockInterval }
            }
        } else {
            clockTimer?.invalidate()
            clockTimer = nil
            animationPhase = 0
        }
    }

    // MARK: - Menu-bar appearance (for the adaptive mono color)

    private func updateAppearance() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        isDarkMenuBar = (match == .darkAqua)
    }

    private func observeAppearance() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateAppearance() }
        }
    }

    private func startFSEvents() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in watcher.reload() }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [store.directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        self.stream = stream
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }
}
