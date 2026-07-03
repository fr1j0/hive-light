import XCTest
@testable import ClaudeLightCore

final class NeedsYouDetectionTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus) -> Session {
        Session(sessionID: id, status: status, project: "p", cwd: "/x/p",
                updatedAt: Date(timeIntervalSince1970: 1_719_745_200))
    }

    // MARK: – needsYou

    func test_needsYou_trueForBlockedStatuses() {
        XCTAssertTrue(needsYou(.waiting))
        XCTAssertTrue(needsYou(.attention))
        XCTAssertTrue(needsYou(.handoff))
        XCTAssertTrue(needsYou(.error))
    }

    func test_needsYou_falseForRunningAndIdle() {
        XCTAssertFalse(needsYou(.running))
        XCTAssertFalse(needsYou(.idle))
    }

    // MARK: – newlyNeedingYou

    func test_transitionFromRunning_isNew() {
        let out = newlyNeedingYou(previous: ["s1": .running], current: [session("s1", .waiting)])
        XCTAssertEqual(out.map(\.sessionID), ["s1"])
    }

    func test_unseenSessionAlreadyRed_isNew() {
        let out = newlyNeedingYou(previous: [:], current: [session("s1", .attention)])
        XCTAssertEqual(out.map(\.sessionID), ["s1"])
    }

    func test_stillRed_isNotNew() {
        let out = newlyNeedingYou(previous: ["s1": .waiting], current: [session("s1", .waiting)])
        XCTAssertTrue(out.isEmpty)
    }

    func test_movingBetweenRedStates_isNotNew() {
        let out = newlyNeedingYou(previous: ["s1": .attention], current: [session("s1", .waiting)])
        XCTAssertTrue(out.isEmpty)
    }

    func test_runningAndIdle_areNeverNew() {
        let out = newlyNeedingYou(previous: [:],
                                  current: [session("s1", .running), session("s2", .idle)])
        XCTAssertTrue(out.isEmpty)
    }

    func test_mixedSessions_onlyTransitionsReturned() {
        let previous: [String: SessionStatus] = ["a": .running, "b": .waiting, "c": .idle]
        let current = [session("a", .attention),   // running → red: new
                       session("b", .handoff),     // red → red: not new
                       session("c", .idle),        // idle: not new
                       session("d", .error)]       // unseen red: new
        let out = newlyNeedingYou(previous: previous, current: current)
        XCTAssertEqual(out.map(\.sessionID), ["a", "d"])
    }

    // MARK: – friendlyStatusLabel (shared by menu rows and notification bodies)

    func test_friendlyStatusLabel_coversAllStatuses() {
        XCTAssertEqual(friendlyStatusLabel(for: .running), "running")
        XCTAssertEqual(friendlyStatusLabel(for: .waiting), "waiting for permission")
        XCTAssertEqual(friendlyStatusLabel(for: .attention), "awaiting your reply")
        XCTAssertEqual(friendlyStatusLabel(for: .handoff), "review requested")
        XCTAssertEqual(friendlyStatusLabel(for: .idle), "idle")
        XCTAssertEqual(friendlyStatusLabel(for: .error), "API error")
    }

    func test_done_isNotNeedsYou() {
        XCTAssertFalse(needsYou(.done))
    }

    func test_runningToDone_isNotNewlyNeedingYou() {
        let session = Session(sessionID: "s1", status: .done, project: "p", cwd: "/p",
                              updatedAt: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertTrue(newlyNeedingYou(previous: ["s1": .running], current: [session]).isEmpty)
    }

    func test_friendlyStatusLabel_done() {
        XCTAssertEqual(friendlyStatusLabel(for: .done), "done")
    }
}
