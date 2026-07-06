import Foundation

public let hiveLightHookRegistrations: [(event: String, matcher: String?)] = [
    ("SessionStart", nil),
    ("UserPromptSubmit", nil),
    ("PreToolUse", "*"),
    ("Stop", nil),
    ("SessionEnd", nil),
    ("Notification", "permission_prompt"),
    ("Notification", "elicitation_dialog"),
]

// Derived from the registrations so the two can never drift out of sync.
public let hiveLightHookEvents: [String] = {
    var seen = Set<String>()
    return hiveLightHookRegistrations.map(\.event).filter { seen.insert($0).inserted }
}()

private func groupCommands(_ group: [String: Any]) -> [String] {
    (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
}

public func installedHooks(into root: [String: Any], command: String) -> [String: Any] {
    var root = root
    // Fix 2: if "hooks" key exists but is not a [String: Any], leave the whole root unchanged.
    if root["hooks"] != nil, (root["hooks"] as? [String: Any]) == nil {
        return root
    }
    var hooks = (root["hooks"] as? [String: Any]) ?? [:]

    for registration in hiveLightHookRegistrations {
        let event = registration.event
        let matcher = registration.matcher
        // Fix 1: cast to [Any] first so non-dict elements don't discard the whole array.
        let rawGroups = (hooks[event] as? [Any]) ?? []
        var groups = rawGroups.compactMap { $0 as? [String: Any] }
        // A registration is satisfied iff some group for this event has our command
        // AND its matcher equals the registration matcher (nil == no "matcher" key).
        let alreadySatisfied = groups.contains { group in
            let hasCmd = groupCommands(group).contains(command)
            let groupMatcher = group["matcher"] as? String
            let matcherMatches: Bool
            if let m = matcher {
                matcherMatches = groupMatcher == m
            } else {
                matcherMatches = groupMatcher == nil
            }
            return hasCmd && matcherMatches
        }
        if !alreadySatisfied {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if let m = matcher { group["matcher"] = m }
            groups.append(group)
        }
        hooks[event] = groups
    }

    root["hooks"] = hooks
    return root
}

public func uninstalledHooks(from root: [String: Any], command: String) -> [String: Any] {
    var root = root
    guard var hooks = root["hooks"] as? [String: Any] else { return root }

    for event in hiveLightHookEvents {
        guard var groups = hooks[event] as? [[String: Any]] else { continue }
        groups = groups.compactMap { group in
            var group = group
            let inner = (group["hooks"] as? [[String: Any]] ?? [])
                .filter { ($0["command"] as? String) != command }
            if inner.isEmpty { return nil }
            group["hooks"] = inner
            return group
        }
        if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
    }

    if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    return root
}

/// True iff any event (ours or not) has an inner hook whose command satisfies
/// `predicate`. Migration scans every event: an old registration set may
/// include events the current list no longer has.
func hooksContainCommand(in root: [String: Any], where predicate: (String) -> Bool) -> Bool {
    guard let hooks = root["hooks"] as? [String: Any] else { return false }
    for value in hooks.values {
        let groups = ((value as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
        if groups.contains(where: { groupCommands($0).contains(where: predicate) }) { return true }
    }
    return false
}

/// Removes every inner hook whose command satisfies `shouldRemove`, across
/// ALL events. Entries without a string command are never touched.
func removedHookCommands(from root: [String: Any], where shouldRemove: (String) -> Bool) -> [String: Any] {
    var root = root
    guard var hooks = root["hooks"] as? [String: Any] else { return root }

    for event in Array(hooks.keys) {
        guard var groups = hooks[event] as? [[String: Any]] else { continue }
        groups = groups.compactMap { group in
            var group = group
            let inner = (group["hooks"] as? [[String: Any]] ?? []).filter { entry in
                guard let cmd = entry["command"] as? String else { return true }
                return !shouldRemove(cmd)
            }
            if inner.isEmpty { return nil }
            group["hooks"] = inner
            return group
        }
        if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
    }

    if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    return root
}

/// Rename migration (#133): if any hook command still references the old
/// binary (matched by `legacyMarker`), drop those entries and install
/// `command` in their place. A root with no legacy entries comes back
/// UNCHANGED — migration never installs for a user who removed the hooks.
public func migratedLegacyHooks(in root: [String: Any],
                                legacyMarker: String,
                                command: String) -> [String: Any] {
    guard hooksContainCommand(in: root, where: { $0.contains(legacyMarker) }) else { return root }
    let cleaned = removedHookCommands(from: root, where: { $0.contains(legacyMarker) })
    return installedHooks(into: cleaned, command: command)
}

/// Returns true iff `root` already contains `command` in any event group's inner hooks.
public func hooksAreInstalled(in root: [String: Any], command: String) -> Bool {
    guard let hooks = root["hooks"] as? [String: Any] else { return false }
    for event in hiveLightHookEvents {
        let rawGroups = (hooks[event] as? [Any]) ?? []
        let groups = rawGroups.compactMap { $0 as? [String: Any] }
        if groups.contains(where: { groupCommands($0).contains(command) }) {
            return true
        }
    }
    return false
}

/// The settings file exists but is not a parseable JSON object. Installing or
/// uninstalling would rewrite the file from scratch and destroy the user's
/// settings, so both refuse instead.
public enum HookInstallerError: Error, Equatable {
    case unparseableSettings
}

public struct HookInstaller {
    public let settingsURL: URL
    public let command: String

    public init(settingsURL: URL, command: String) {
        self.settingsURL = settingsURL
        self.command = command
    }

    /// A missing file is a fresh start ([:]); an existing file that can't be read
    /// or parsed as a JSON object throws — proceeding would rewrite the user's
    /// settings from scratch (#40).
    private func loadRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw HookInstallerError.unparseableSettings }
        return obj
    }

    private func save(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Returns true iff the hook command is currently present in the settings file on disk.
    public func isInstalled() -> Bool {
        let root = (try? loadRoot()) ?? [:]
        return hooksAreInstalled(in: root, command: command)
    }

    public func install() throws {
        try save(installedHooks(into: try loadRoot(), command: command))
    }

    public func uninstall() throws {
        try save(uninstalledHooks(from: try loadRoot(), command: command))
    }

    /// Rename migration (#133): rewrites hook entries left by the old app
    /// (matched by `marker` in their command) to this installer's command.
    /// Returns true iff the file changed. A missing file has nothing to
    /// migrate; an unparseable one throws, like install/uninstall — never
    /// rewrite a settings file we can't read.
    public func migrateLegacy(marker: String) throws -> Bool {
        let root = try loadRoot()
        guard hooksContainCommand(in: root, where: { $0.contains(marker) }) else { return false }
        try save(migratedLegacyHooks(in: root, legacyMarker: marker, command: command))
        return true
    }
}
