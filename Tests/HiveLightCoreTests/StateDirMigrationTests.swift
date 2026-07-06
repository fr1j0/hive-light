import XCTest
@testable import HiveLightCore

/// Rename migration (#133): ~/.claude-light → ~/.hive-light, one-time move.
final class StateDirMigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var legacy: URL { root.appendingPathComponent(".claude-light", isDirectory: true) }
    private var current: URL { root.appendingPathComponent(".hive-light", isDirectory: true) }

    func testMovesLegacyDirWithContents() throws {
        let sessions = legacy.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: sessions.appendingPathComponent("abc.json"))

        migrateLegacyStateDir(from: legacy, to: current)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: current.appendingPathComponent("sessions/abc.json").path))
    }

    func testNoOpWhenCurrentAlreadyExists() throws {
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appendingPathComponent("marker"))
        let currentSessions = current.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: currentSessions, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: currentSessions.appendingPathComponent("live.json"))

        migrateLegacyStateDir(from: legacy, to: current)

        // Both stay: never merge, never overwrite live state.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("marker").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: currentSessions.appendingPathComponent("live.json").path))
    }

    func testNoOpWhenLegacyMissing() {
        migrateLegacyStateDir(from: legacy, to: current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
    }

    func testLegacyFileNotDirIsIgnored() throws {
        try Data("not a dir".utf8).write(to: legacy)
        migrateLegacyStateDir(from: legacy, to: current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }
}
