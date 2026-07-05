import XCTest
@testable import ClaudeLightCore

final class PanelModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func s(_ status: SessionStatus, detail: String? = nil,
                   ageSeconds: TimeInterval = 0, cwd: String = "/x/vatios") -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "vatios", cwd: cwd,
                updatedAt: now.addingTimeInterval(-ageSeconds), tty: "ttys000", detail: detail)
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

    func test_subagentChipText_pluralAndFailed() {
        let list = SubagentList(visible: [
            Subagent(id: "1", label: "a", state: .running),
            Subagent(id: "2", label: "b", state: .failed),
            Subagent(id: "3", label: "c", state: .running),
        ], overflowRunning: 1)
        XCTAssertEqual(subagentChipText(list), "⑂ 4 subagents · 1 failed")
    }

    func test_subagentChipText_singularNoFailures() {
        let list = SubagentList(visible: [Subagent(id: "1", label: "a", state: .running)],
                                overflowRunning: 0)
        XCTAssertEqual(subagentChipText(list), "⑂ 1 subagent")
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
}
