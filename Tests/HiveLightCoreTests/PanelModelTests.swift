import XCTest
@testable import HiveLightCore

final class PanelModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func s(_ status: SessionStatus, detail: String? = nil,
                   ageSeconds: TimeInterval = 0, cwd: String = "/x/vatios",
                   branch: String? = nil) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "vatios", cwd: cwd,
                updatedAt: now.addingTimeInterval(-ageSeconds), tty: "ttys000", detail: detail,
                branch: branch)
    }

    func test_cardTitle_isDisplayName() {
        XCTAssertEqual(cardTitle(for: s(.running)), "vatios")
    }

    func test_cardSubtitle_detailWinsOverLabel() {
        XCTAssertEqual(cardSubtitle(for: s(.attention, detail: "Deploy where?"), errorReason: nil),
                       "Deploy where?")
    }

    func test_cardSubtitle_fallsBackToFriendlyLabel() {
        XCTAssertEqual(cardSubtitle(for: s(.attention), errorReason: nil), "awaiting your reply")
        XCTAssertEqual(cardSubtitle(for: s(.running), errorReason: nil), "running")
    }

    func test_cardSubtitle_errorBeatsDetail() {
        XCTAssertEqual(cardSubtitle(for: s(.error, detail: "stale"), errorReason: "rate limited"),
                       "API error: rate limited")
        XCTAssertEqual(cardSubtitle(for: s(.error), errorReason: nil), "API error: api error")
    }

    func test_timerText_formatsAge() {
        XCTAssertEqual(timerText(for: s(.attention, ageSeconds: 720), now: now), "12m")
        XCTAssertEqual(timerText(for: s(.running, ageSeconds: 45), now: now), "45s")
    }

    func test_subagentChipText_countAndFailed() {
        let list = SubagentList(visible: [], total: 5, doneCount: 3, failedCount: 1)
        XCTAssertEqual(subagentChipText(list), "3 of 5 done · 1 failed")
    }

    func test_subagentChipText_countNoFailures() {
        let list = SubagentList(visible: [], total: 5, doneCount: 3, failedCount: 0)
        XCTAssertEqual(subagentChipText(list), "3 of 5 done")
    }

    func test_accessibilityLabel_matchesOldMenuRow() {
        XCTAssertEqual(accessibilityLabel(for: s(.waiting)), "vatios — waiting for permission")
    }

    func test_contextSegments_boundaries() {
        XCTAssertEqual(contextSegments(fraction: 0.01), 1)
        XCTAssertEqual(contextSegments(fraction: 0.46), 3)
        XCTAssertEqual(contextSegments(fraction: 0.75), 4)
        XCTAssertEqual(contextSegments(fraction: 0.9), 5)
        XCTAssertEqual(contextSegments(fraction: 1.0), 5)
    }

    func test_contextLevel_thresholds() {
        XCTAssertEqual(contextLevel(fraction: 0.74), .ok)
        XCTAssertEqual(contextLevel(fraction: 0.75), .warm)
        XCTAssertEqual(contextLevel(fraction: 0.89), .warm)
        XCTAssertEqual(contextLevel(fraction: 0.9), .hot)
    }

    func test_contextTooltip_wording() {
        XCTAssertEqual(contextTooltip(fraction: 0.78), "context 78% used")
    }

    // MARK: – branch-in-subtitle (#82)

    func test_cardSubtitle_idleBranch_showsBranch() {
        let session = s(.idle, branch: "feat/x")
        XCTAssertEqual(cardSubtitle(for: session, errorReason: nil), "feat/x")
        XCTAssertTrue(subtitleShowsBranch(for: session))
    }

    func test_cardSubtitle_waitingWithBranch_keepsFriendlyLabel() {
        let session = s(.waiting, branch: "feat/x")
        XCTAssertEqual(cardSubtitle(for: session, errorReason: nil),
                       friendlyStatusLabel(for: .waiting))
        XCTAssertFalse(subtitleShowsBranch(for: session))
    }

    func test_cardSubtitle_runningWithBranchAndDetail_detailWins() {
        let session = s(.running, detail: "Deploy where?", branch: "feat/x")
        XCTAssertEqual(cardSubtitle(for: session, errorReason: nil), "Deploy where?")
        XCTAssertFalse(subtitleShowsBranch(for: session))
    }

    func test_cardSubtitle_errorWithBranch_showsError() {
        let session = s(.error, branch: "feat/x")
        XCTAssertEqual(cardSubtitle(for: session, errorReason: "rate limited"),
                       "API error: rate limited")
        XCTAssertFalse(subtitleShowsBranch(for: session))
    }

    func test_taskHistoryToggleText_countFreeLabel() {
        let many = TaskSummary(inProgressSubject: "Now", total: 8,
                               doneSubjects: ["1", "2", "3", "4", "5", "A", "B"])
        XCTAssertEqual(taskHistoryToggleText(many), "earlier tasks")
        let one = TaskSummary(inProgressSubject: "Now", total: 2,
                              doneSubjects: ["A"])
        XCTAssertEqual(taskHistoryToggleText(one), "earlier tasks")
        let none = TaskSummary(inProgressSubject: "Now", total: 1,
                               doneSubjects: [])
        XCTAssertNil(taskHistoryToggleText(none))
    }

    func test_taskLineText_subjectDotCounts() {
        // "tasks" suffix disambiguates the count from the subagent block's
        // "X of N done" directly below it.
        let summary = TaskSummary(inProgressSubject: "Task 6: AGENTS.md docs + quality gate",
                                  total: 7, doneSubjects: ["1", "2", "3", "4", "5"])
        XCTAssertEqual(taskLineText(summary), "Task 6: AGENTS.md docs + quality gate · 5/7 tasks")
    }
}
