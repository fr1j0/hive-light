import XCTest
@testable import HiveLightCore

/// #167: sessions that have only ever seen SessionStart (idle, and never
/// updated since birth) expire on a short TTL — ghosts from tab-closes and
/// aborted launches vanish in minutes instead of haunting the hive for the
/// full 8-hour default. A real-but-unused REPL reappears on its first prompt.
final class UnpromptedTTLTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ status: SessionStatus, ageSeconds: TimeInterval,
                         unprompted: Bool, startedAt: Date?? = nil) -> Session {
        let updated = Date(timeIntervalSince1970: 1_000_000 - ageSeconds)
        let started: Date?
        if let explicit = startedAt {
            started = explicit
        } else {
            started = unprompted ? updated : updated.addingTimeInterval(-600)
        }
        return Session(sessionID: UUID().uuidString, status: status, project: "p",
                       cwd: "/p", updatedAt: updated, startedAt: started)
    }

    // MARK: sessionTTL(for:)

    func test_unpromptedIdleSession_getsShortTTL() {
        let ghost = session(.idle, ageSeconds: 0, unprompted: true)
        XCTAssertEqual(sessionTTL(for: ghost), unpromptedSessionTTL)
    }

    func test_promptedSession_keepsDefaultTTL() {
        let real = session(.idle, ageSeconds: 0, unprompted: false)
        XCTAssertEqual(sessionTTL(for: real), defaultSessionTTL)
    }

    func test_nilStartedAt_legacyFile_keepsDefaultTTL() {
        let legacy = session(.idle, ageSeconds: 0, unprompted: false, startedAt: .some(nil))
        XCTAssertEqual(sessionTTL(for: legacy), defaultSessionTTL)
    }

    func test_runningSessionBornThisInstant_keepsDefaultTTL() {
        // Belt-and-braces: only idle sessions qualify as unprompted.
        let odd = session(.running, ageSeconds: 0, unprompted: true)
        XCTAssertEqual(sessionTTL(for: odd), defaultSessionTTL)
    }

    // MARK: liveSessions

    func test_liveSessions_dropsUnpromptedPastShortTTL() {
        let ghost = session(.idle, ageSeconds: 16 * 60, unprompted: true)
        XCTAssertEqual(liveSessions([ghost], now: now).count, 0)
    }

    func test_liveSessions_keepsYoungUnprompted() {
        let fresh = session(.idle, ageSeconds: 14 * 60, unprompted: true)
        XCTAssertEqual(liveSessions([fresh], now: now).count, 1)
    }

    func test_liveSessions_keepsHoursOldPromptedIdle() {
        // The generous default TTL is untouched for real sessions.
        let real = session(.idle, ageSeconds: 3 * 3600, unprompted: false)
        XCTAssertEqual(liveSessions([real], now: now).count, 1)
    }

    func test_liveSessions_explicitTightTTL_stillCapsPrompted() {
        // Callers passing an explicit ttl keep their cap for real sessions.
        let real = session(.running, ageSeconds: 3600, unprompted: false)
        XCTAssertEqual(liveSessions([real], now: now, ttl: 1800).count, 0)
    }

    // MARK: prune

    func test_prune_deletesOldUnprompted_keepsYoungAndPrompted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hive-light-unprompted-\(UUID().uuidString)")
        let store = SessionStore(directory: dir)
        let ghost = session(.idle, ageSeconds: 16 * 60, unprompted: true)
        let fresh = session(.idle, ageSeconds: 14 * 60, unprompted: true)
        let real = session(.idle, ageSeconds: 3 * 3600, unprompted: false)
        try store.write(ghost); try store.write(fresh); try store.write(real)

        store.prune(now: now)

        let remaining = Set(try store.loadAll().map(\.sessionID))
        XCTAssertEqual(remaining, [fresh.sessionID, real.sessionID])
    }
}
