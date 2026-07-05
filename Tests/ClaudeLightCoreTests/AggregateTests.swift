import XCTest
@testable import ClaudeLightCore

final class AggregateTests: XCTestCase {
    private func s(_ status: SessionStatus, ageSeconds: TimeInterval = 0) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000 - ageSeconds))
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_emptyIsGreen() {
        XCTAssertEqual(aggregateLight(for: []), .green)
    }

    func test_redWinsOverOrangeAndGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.running), s(.waiting)]), .red)
    }

    func test_orangeWinsOverGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.running)]), .orange)
    }

    func test_allIdleIsGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.idle)]), .green)
    }

    func test_liveSessions_dropsStale() {
        let fresh = s(.running, ageSeconds: 60)
        let stale = s(.waiting, ageSeconds: 3600)
        let live = liveSessions([fresh, stale], now: now, ttl: 1800)
        XCTAssertEqual(live.map(\.sessionID), [fresh.sessionID])
    }

    func test_liveSessions_keepsExactlyAtTTL() {
        let edge = s(.running, ageSeconds: 1800)
        XCTAssertEqual(liveSessions([edge], now: now, ttl: 1800).count, 1)
    }

    func test_liveSessions_defaultTTL_keepsHoursOldIdleSession() {
        // A session you leave open and idle for a few hours must not vanish.
        XCTAssertEqual(liveSessions([s(.idle, ageSeconds: 3 * 3600)], now: now).count, 1)
    }

    func test_liveSessions_defaultTTL_dropsVeryOldSession() {
        // But a session with no hook events for most of a day ages out (likely dead).
        XCTAssertEqual(liveSessions([s(.idle, ageSeconds: 9 * 3600)], now: now).count, 0)
    }

    func test_attentionSession_isRed() {
        XCTAssertEqual(aggregateLight(for: [s(.attention)]), .red)
    }

    func test_attentionSession_needsAttentionTrue() {
        XCTAssertTrue(aggregateNeedsAttention([s(.attention)]))
    }

    func test_waitingSession_isRedButNotNeedsAttention() {
        XCTAssertEqual(aggregateLight(for: [s(.waiting)]), .red)
        XCTAssertFalse(aggregateNeedsAttention([s(.waiting)]))
    }

    func test_noAttentionSessions_needsAttentionFalse() {
        XCTAssertFalse(aggregateNeedsAttention([s(.running), s(.idle)]))
    }

    func test_emptyNeedsAttentionFalse() {
        XCTAssertFalse(aggregateNeedsAttention([]))
    }

    func test_handoffSession_isRedButNotNeedsAttention() {
        XCTAssertEqual(aggregateLight(for: [s(.handoff)]), .red)
        XCTAssertFalse(aggregateNeedsAttention([s(.handoff)]))
    }

}
