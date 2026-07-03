import XCTest
@testable import ClaudeLightCore

final class SessionStoreTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-tests-\(UUID().uuidString)")
        return SessionStore(directory: dir)
    }

    private func makeSession(_ id: String, _ status: SessionStatus) -> Session {
        Session(sessionID: id, status: status, project: "p", cwd: "/tmp/p",
                updatedAt: Date(timeIntervalSince1970: 1_719_745_200))
    }

    func test_write_then_loadAll_returnsSession() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionID, "a")
        XCTAssertEqual(all.first?.status, .running)
    }

    func test_write_isUpsert() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try store.write(makeSession("a", .idle))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .idle)
    }

    func test_delete_removesFile_andIsIdempotent() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try store.delete(sessionID: "a")
        XCTAssertEqual(try store.loadAll().count, 0)
        XCTAssertNoThrow(try store.delete(sessionID: "a")) // already gone
    }

    func test_loadAll_onMissingDirectory_returnsEmpty() throws {
        let store = tempStore() // never created
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    // MARK: – load(sessionID:)

    func test_load_returnsStoredSession() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        let s = store.load(sessionID: "a")
        XCTAssertEqual(s?.sessionID, "a")
        XCTAssertEqual(s?.status, .running)
    }

    func test_load_returnsNil_whenMissingOrCorrupt() throws {
        let store = tempStore()
        XCTAssertNil(store.load(sessionID: "missing"))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL(for: "broken"))
        XCTAssertNil(store.load(sessionID: "broken"))
    }

    // MARK: – prune (#42)

    func test_prune_deletesExpiredSessions_keepsFresh() throws {
        let store = tempStore()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var fresh = makeSession("fresh", .idle)
        fresh.updatedAt = now.addingTimeInterval(-60)
        var expired = makeSession("expired", .idle)
        expired.updatedAt = now.addingTimeInterval(-defaultSessionTTL - 60)
        try store.write(fresh)
        try store.write(expired)
        store.prune(now: now)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: "fresh").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: "expired").path))
    }

    func test_prune_deletesStaleCorruptFiles_keepsRecentCorrupt() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let staleURL = store.fileURL(for: "stale-corrupt")
        let recentURL = store.fileURL(for: "recent-corrupt")
        try Data("not json".utf8).write(to: staleURL)
        try Data("not json".utf8).write(to: recentURL)
        // Backdate the stale file's mtime past the TTL; "now" is the real clock here.
        let old = Date().addingTimeInterval(-defaultSessionTTL - 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: staleURL.path)
        store.prune(now: Date())
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentURL.path))
    }

    func test_prune_onMissingDirectory_isNoOp() {
        let store = tempStore() // never created
        store.prune(now: Date())
    }

    func test_loadAll_skipsCorruptFiles() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL(for: "broken"))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionID, "a")
    }
}
