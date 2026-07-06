import XCTest
@testable import HiveLightCore

/// Rename migration (#133): settings.json entries pointing at the old
/// "…/Claude Light.app/…/claude-light-hook" binary are dead after the app
/// renames; they must be rewritten to the new command exactly once.
final class HookMigrationTests: XCTestCase {
    let legacyCmd = "'/Applications/Claude Light.app/Contents/MacOS/claude-light-hook'"
    let newCmd = "'/Applications/Hive Light.app/Contents/MacOS/hive-light-hook'"
    let marker = "claude-light-hook"

    private func commands(_ root: [String: Any], _ event: String) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []) }
            .compactMap { $0["command"] as? String }
    }

    func test_rewritesLegacyEntriesToNewCommand() {
        let root = installedHooks(into: [:], command: legacyCmd)
        let out = migratedLegacyHooks(in: root, legacyMarker: marker, command: newCmd)
        for event in hiveLightHookEvents {
            XCTAssertTrue(commands(out, event).contains(newCmd), "missing new cmd on \(event)")
            XCTAssertFalse(commands(out, event).contains(legacyCmd), "stale cmd on \(event)")
        }
    }

    func test_noLegacyEntries_returnsRootUnchanged() {
        // Never installs on migration — a user who removed hooks stays removed.
        let out = migratedLegacyHooks(in: [:], legacyMarker: marker, command: newCmd)
        XCTAssertNil(out["hooks"])

        let fresh = installedHooks(into: [:], command: newCmd)
        let migratedFresh = migratedLegacyHooks(in: fresh, legacyMarker: marker, command: newCmd)
        XCTAssertEqual(
            NSDictionary(dictionary: migratedFresh), NSDictionary(dictionary: fresh))
    }

    func test_foreignHooksSurviveMigration() {
        var root = installedHooks(into: [:], command: legacyCmd)
        var hooks = root["hooks"] as! [String: Any]
        var stopGroups = hooks["Stop"] as! [[String: Any]]
        stopGroups.append(["hooks": [["type": "command", "command": "afplay done.aiff"]]])
        hooks["Stop"] = stopGroups
        root["hooks"] = hooks

        let out = migratedLegacyHooks(in: root, legacyMarker: marker, command: newCmd)
        XCTAssertTrue(commands(out, "Stop").contains("afplay done.aiff"))
        XCTAssertTrue(commands(out, "Stop").contains(newCmd))
        XCTAssertFalse(commands(out, "Stop").contains(legacyCmd))
    }

    func test_legacyEntryUnderForeignEvent_isAlsoRemoved() {
        // Robustness: an old registration set may include events the current
        // registration list no longer has — the marker match must find them.
        let root: [String: Any] = ["hooks": [
            "PostToolUse": [["hooks": [["type": "command", "command": legacyCmd]]]]
        ]]
        let out = migratedLegacyHooks(in: root, legacyMarker: marker, command: newCmd)
        XCTAssertFalse(commands(out, "PostToolUse").contains(legacyCmd))
        XCTAssertTrue(commands(out, "SessionStart").contains(newCmd))
    }

    func test_relocatedCurrentBinary_isRewrittenToCurrentPath() {
        // Self-heal app moves (dist → /Applications, manual → brew): the
        // marker can be the CURRENT binary name; only exact-path matches stay.
        let moved = installedHooks(
            into: [:], command: "'/tmp/dist/Hive Light.app/Contents/MacOS/hive-light-hook'")
        let out = migratedLegacyHooks(in: moved, legacyMarker: "hive-light-hook", command: newCmd)
        for event in hiveLightHookEvents {
            XCTAssertTrue(commands(out, event).contains(newCmd))
            XCTAssertFalse(commands(out, event).contains { $0.contains("/tmp/dist/") })
        }
    }

    func test_currentCommandExactMatch_isNeverStale() {
        let fresh = installedHooks(into: [:], command: newCmd)
        let out = migratedLegacyHooks(in: fresh, legacyMarker: "hive-light-hook", command: newCmd)
        XCTAssertEqual(NSDictionary(dictionary: out), NSDictionary(dictionary: fresh))
    }

    // MARK: - File-level (HookInstaller.migrateLegacy)

    func test_installer_migratesFileOnceAndReportsChange() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")

        let legacyRoot = installedHooks(into: [:], command: legacyCmd)
        try JSONSerialization.data(withJSONObject: legacyRoot).write(to: url)

        let installer = HookInstaller(settingsURL: url, command: newCmd)
        XCTAssertTrue(try installer.migrateLegacy(marker: marker))
        XCTAssertTrue(installer.isInstalled())
        // Second run: nothing legacy left, no write needed — with either
        // marker, including the current binary's own name.
        XCTAssertFalse(try installer.migrateLegacy(marker: marker))
        XCTAssertFalse(try installer.migrateLegacy(marker: "hive-light-hook"))
    }

    func test_installer_migrate_missingFile_isNoOp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString).json")
        let installer = HookInstaller(settingsURL: url, command: newCmd)
        XCTAssertFalse(try installer.migrateLegacy(marker: marker))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
