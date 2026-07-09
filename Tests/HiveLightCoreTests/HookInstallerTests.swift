import XCTest
@testable import HiveLightCore

final class HookInstallerTests: XCTestCase {
    let cmd = "/Applications/Hive Light.app/Contents/MacOS/hive-light-hook"

    /// All commands across all groups for an event.
    private func commands(_ root: [String: Any], _ event: String) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []) }
            .compactMap { $0["command"] as? String }
    }

    /// Groups for `event` whose inner hooks contain `cmd`.
    private func ourGroups(_ root: [String: Any], _ event: String) -> [[String: Any]] {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.filter { group in
            let cmds = (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
            return cmds.contains(cmd)
        }
    }

    // MARK: – Basic install

    func test_install_addsAllSevenEvents() {
        let out = installedHooks(into: [:], command: cmd)
        XCTAssertEqual(Set(hiveLightHookEvents),
                       ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                        "Stop", "SessionEnd", "Notification"])
        for event in hiveLightHookEvents {
            XCTAssertTrue(commands(out, event).contains(cmd), "missing \(event)")
        }
    }

    // MARK: – Notification produces two matcher groups

    func test_install_notification_hasTwoMatcherGroups() throws {
        let out = installedHooks(into: [:], command: cmd)
        let groups = ourGroups(out, "Notification")
        XCTAssertEqual(groups.count, 2, "expected exactly 2 Notification groups for our command")
        let matchers = Set(groups.compactMap { $0["matcher"] as? String })
        XCTAssertEqual(matchers, ["permission_prompt", "elicitation_dialog"])
    }

    // MARK: – Matchers on other events

    func test_preToolUse_groupHasMatcher() throws {
        let out = installedHooks(into: [:], command: cmd)
        let hooks = try XCTUnwrap(out["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        let ours = groups.first { ($0["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == cmd } == true }
        XCTAssertEqual(ours?["matcher"] as? String, "*")
    }

    func test_postToolUse_groupHasMatcher() throws {
        let out = installedHooks(into: [:], command: cmd)
        let hooks = try XCTUnwrap(out["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["PostToolUse"] as? [[String: Any]])
        let ours = groups.first { ($0["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == cmd } == true }
        XCTAssertEqual(ours?["matcher"] as? String, "*")
    }

    func test_eventsWithoutMatcher_haveNoMatcherKey() throws {
        let out = installedHooks(into: [:], command: cmd)
        for event in ["Stop", "SessionStart", "UserPromptSubmit", "SessionEnd"] {
            let groups = ourGroups(out, event)
            XCTAssertEqual(groups.count, 1, "\(event) should have exactly 1 group")
            XCTAssertNil(groups.first?["matcher"], "\(event) group should have no matcher key")
        }
    }

    // MARK: – Idempotency

    func test_install_isIdempotent_stop() {
        let once = installedHooks(into: [:], command: cmd)
        let twice = installedHooks(into: once, command: cmd)
        XCTAssertEqual(commands(twice, "Stop").filter { $0 == cmd }.count, 1)
    }

    func test_install_isIdempotent_notification() {
        let once = installedHooks(into: [:], command: cmd)
        let twice = installedHooks(into: once, command: cmd)
        XCTAssertEqual(ourGroups(twice, "Notification").count, 2,
                       "double-install must not duplicate Notification groups")
    }

    // MARK: – Preserves unrelated hooks

    func test_install_preservesExistingUnrelatedHooks() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]]]
        ]
        let out = installedHooks(into: existing, command: cmd)
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
        XCTAssertTrue(commands(out, "Stop").contains(cmd))
    }

    func test_install_preservesUnrelatedNotificationGroup() throws {
        let existing: [String: Any] = [
            "hooks": [
                "Notification": [
                    ["matcher": "some_other_matcher",
                     "hooks": [["type": "command", "command": "/other/tool"]]]
                ]
            ]
        ]
        let out = installedHooks(into: existing, command: cmd)
        let hooks = try XCTUnwrap(out["hooks"] as? [String: Any])
        let notifGroups = try XCTUnwrap(hooks["Notification"] as? [[String: Any]])
        // 1 unrelated + 2 ours
        XCTAssertEqual(notifGroups.count, 3)
        XCTAssertTrue(commands(out, "Notification").contains("/other/tool"))
    }

    // MARK: – Uninstall

    func test_uninstall_removesOurs_keepsOthers() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]]]
        ]
        let installed = installedHooks(into: existing, command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertFalse(commands(out, "Stop").contains(cmd))
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
    }

    func test_uninstall_removesAllNotificationGroups() {
        let installed = installedHooks(into: [:], command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertEqual(ourGroups(out, "Notification").count, 0)
    }

    func test_uninstall_fromOnlyOurs_leavesNoEmptyHooksKey() {
        let installed = installedHooks(into: [:], command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertNil(out["hooks"])
    }

    func test_uninstall_keepsUnrelatedNotificationGroup() {
        let existing: [String: Any] = [
            "hooks": [
                "Notification": [
                    ["matcher": "some_other_matcher",
                     "hooks": [["type": "command", "command": "/other/tool"]]]
                ]
            ]
        ]
        let installed = installedHooks(into: existing, command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertEqual(ourGroups(out, "Notification").count, 0)
        XCTAssertTrue(commands(out, "Notification").contains("/other/tool"))
    }

    // MARK: – Malformed-JSON regression

    func test_install_preservesExistingGroups_whenArrayHasNonDictElement() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]], "junk-string"]]
        ]
        let out = installedHooks(into: existing, command: cmd)
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
        XCTAssertTrue(commands(out, "Stop").contains(cmd))
    }

    func test_install_leavesMalformedHooksValueUntouched() {
        let existing: [String: Any] = ["hooks": ["not", "an", "object"]]
        let out = installedHooks(into: existing, command: cmd)
        XCTAssertTrue(out["hooks"] is [Any])
        XCTAssertEqual((out["hooks"] as? [String])?.count, 3)
    }

    // MARK: – Unparseable settings must never be overwritten (#40)

    private func tempSettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
    }

    func test_install_throwsAndPreservesFile_whenSettingsUnparseable() throws {
        let url = tempSettingsURL()
        let original = Data(#"{"model": "opus""#.utf8)   // truncated file → invalid JSON
        try original.write(to: url)
        let installer = HookInstaller(settingsURL: url, command: cmd)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertTrue(error is HookInstallerError)
        }
        XCTAssertEqual(try Data(contentsOf: url), original, "file must be left byte-for-byte untouched")
    }

    func test_install_throwsAndPreservesFile_whenTopLevelIsNotAnObject() throws {
        let url = tempSettingsURL()
        let original = Data(#"["not", "an", "object"]"#.utf8)
        try original.write(to: url)
        let installer = HookInstaller(settingsURL: url, command: cmd)
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try Data(contentsOf: url), original, "file must be left byte-for-byte untouched")
    }

    func test_uninstall_throwsAndPreservesFile_whenSettingsUnparseable() throws {
        let url = tempSettingsURL()
        let original = Data(#"{"model": "opus""#.utf8)   // truncated file → invalid JSON
        try original.write(to: url)
        let installer = HookInstaller(settingsURL: url, command: cmd)
        XCTAssertThrowsError(try installer.uninstall())
        XCTAssertEqual(try Data(contentsOf: url), original, "file must be left byte-for-byte untouched")
    }

    func test_install_stillWorks_whenFileIsMissing() throws {
        let url = tempSettingsURL()
        let installer = HookInstaller(settingsURL: url, command: cmd)
        try installer.install()
        XCTAssertTrue(installer.isInstalled())
    }

    // MARK: – hooksAreInstalled pure helper

    func test_hooksAreInstalled_falseOnEmpty() {
        XCTAssertFalse(hooksAreInstalled(in: [:], command: cmd))
    }

    func test_hooksAreInstalled_trueAfterInstall() {
        let installed = installedHooks(into: [:], command: cmd)
        XCTAssertTrue(hooksAreInstalled(in: installed, command: cmd))
    }

    func test_hooksAreInstalled_falseAfterUninstall() {
        let installed = installedHooks(into: [:], command: cmd)
        let removed = uninstalledHooks(from: installed, command: cmd)
        XCTAssertFalse(hooksAreInstalled(in: removed, command: cmd))
    }

    // MARK: – HookInstaller.isInstalled() disk method

    func test_isInstalled_diskRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        let installer = HookInstaller(settingsURL: url, command: cmd)
        XCTAssertFalse(installer.isInstalled(), "no file → false")
        try Data("{}".utf8).write(to: url)
        XCTAssertFalse(installer.isInstalled(), "empty object → false")
        try installer.install()
        XCTAssertTrue(installer.isInstalled(), "after install → true")
        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled(), "after uninstall → false")
    }

    func test_diskRoundTrip_installThenUninstall() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        try HookInstaller(settingsURL: url, command: cmd).install()
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertTrue(commands(root, "Stop").contains(cmd))
        try HookInstaller(settingsURL: url, command: cmd).uninstall()
        root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertNil(root["hooks"])
    }
}
