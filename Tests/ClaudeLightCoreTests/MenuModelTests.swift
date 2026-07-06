import XCTest
@testable import ClaudeLightCore

final class MenuModelTests: XCTestCase {
    private func s(_ status: SessionStatus, project: String = "p",
                   id: String = UUID().uuidString,
                   started: TimeInterval? = nil,
                   updated: TimeInterval = 1_000_000) -> Session {
        Session(sessionID: id, status: status, project: project, cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: updated),
                startedAt: started.map(Date.init(timeIntervalSince1970:)))
    }

    func test_counts_bucketsWaitingAndAttentionTogether() {
        let c = statusCounts(for: [s(.waiting), s(.attention), s(.running), s(.idle), s(.idle)])
        XCTAssertEqual(c, StatusCounts(needYou: 2, working: 1, idle: 2, error: 0))
    }
    func test_summary_nilWhenEmpty() {
        XCTAssertNil(summaryText(for: StatusCounts(needYou: 0, working: 0, idle: 0, error: 0)))
    }
    func test_summary_singularNeedsYou() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 1, working: 0, idle: 0, error: 0)), "1 needs you")
    }
    func test_summary_pluralAndWorking() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 2, working: 3, idle: 1, error: 0)), "2 need you · 3 working")
    }
    func test_summary_idleOnly() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 0, working: 0, idle: 4, error: 0)), "Idle")
    }
    func test_summary_workingOnly() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 0, working: 2, idle: 0, error: 0)), "2 working")
    }
    func test_counts_includeError() {
        let c = statusCounts(for: [s(.error), s(.error), s(.running), s(.idle)])
        XCTAssertEqual(c, StatusCounts(needYou: 0, working: 1, idle: 1, error: 2))
    }
    func test_summary_errorsBreakOut() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 0, working: 2, idle: 0, error: 1)), "1 error · 2 working")
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 1, working: 0, idle: 0, error: 2)), "2 errors · 1 needs you")
    }
    func test_sorted_errorFirst() {
        // Chronological: status carries NO positional weight — a red session
        // stays where its start time put it (the list is a navigation index).
        let order = sortedForMenu([s(.idle, project: "z", started: 400),
                                   s(.running, project: "r", started: 100),
                                   s(.error, project: "e", started: 300),
                                   s(.attention, project: "a", started: 200)])
            .map { "\($0.status.rawValue):\($0.project)" }
        XCTAssertEqual(order, ["running:r", "attention:a", "error:e", "idle:z"])
    }
}

extension MenuModelTests {
    func test_sorted_statusFlipDoesNotMoveRows() {
        // The same list before and after a status change keeps one order.
        let a = s(.running, project: "a", id: "A", started: 100)
        let b = s(.running, project: "b", id: "B", started: 200)
        let before = sortedForMenu([b, a]).map(\.sessionID)
        var aRed = a; aRed.status = .attention
        let after = sortedForMenu([b, aRed]).map(\.sessionID)
        XCTAssertEqual(before, after)
        XCTAssertEqual(after, ["A", "B"])
    }

    func test_sorted_nilStartedAt_isStable_notUpdatedAtDriven() {
        // Old-hook files (no started_at) must NOT shuffle as updatedAt moves:
        // they sort as distant past (stable id order), before stamped rows.
        let old1 = s(.idle, project: "old1", id: "B", updated: 999)
        let old2 = s(.running, project: "old2", id: "A", updated: 50)
        let stamped = s(.running, project: "new", started: 100, updated: 10)
        XCTAssertEqual(sortedForMenu([stamped, old1, old2]).map(\.project),
                       ["old2", "old1", "new"])
        // updatedAt drift changes nothing.
        var bumped = old1; bumped.updatedAt = Date(timeIntervalSince1970: 5)
        XCTAssertEqual(sortedForMenu([stamped, bumped, old2]).map(\.project),
                       ["old2", "old1", "new"])
    }

    func test_sorted_tieBreak_bySessionID() {
        let x = s(.idle, project: "x", id: "2", started: 100)
        let y = s(.idle, project: "y", id: "1", started: 100)
        XCTAssertEqual(sortedForMenu([x, y]).map(\.sessionID), ["1", "2"])
    }

    func test_relativeTime_boundaries() {
        XCTAssertEqual(relativeTime(secondsAgo: -5), "0s")
        XCTAssertEqual(relativeTime(secondsAgo: 0), "0s")
        XCTAssertEqual(relativeTime(secondsAgo: 59), "59s")
        XCTAssertEqual(relativeTime(secondsAgo: 60), "1m")
        XCTAssertEqual(relativeTime(secondsAgo: 3599), "59m")
        XCTAssertEqual(relativeTime(secondsAgo: 3600), "1h")
        XCTAssertEqual(relativeTime(secondsAgo: 86399), "23h")
        XCTAssertEqual(relativeTime(secondsAgo: 86400), "1d")
    }

    func test_counts_handoffFoldsIntoNeedYou() {
        let c = statusCounts(for: [s(.handoff), s(.waiting), s(.running)])
        XCTAssertEqual(c, StatusCounts(needYou: 2, working: 1, idle: 0, error: 0))
    }

    func test_sorted_chronological_ignoresStatusEntirely() {
        let input = [
            s(.idle, project: "z", started: 40),
            s(.waiting, project: "w", started: 30),
            s(.running, project: "r", started: 10),
            s(.handoff, project: "h", started: 20),
        ]
        let order = sortedForMenu(input).map { "\($0.status.rawValue):\($0.project)" }
        XCTAssertEqual(order, ["running:r", "handoff:h", "waiting:w", "idle:z"])
    }

}
