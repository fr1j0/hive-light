import XCTest
@testable import HiveLightCore

final class IconModelTests: XCTestCase {
    private func s(_ status: SessionStatus) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }
    private func st(_ r: LampMotion, _ o: LampMotion, _ g: LampMotion) -> IconState {
        IconState(red: r, orange: o, green: g)
    }

    func test_none_allOff()          { XCTAssertEqual(iconState(for: []), st(.off, .off, .off)) }
    func test_idleOnly_green()       { XCTAssertEqual(iconState(for: [s(.idle)]), st(.off, .off, .steady)) }
    func test_runningOnly_orange()   { XCTAssertEqual(iconState(for: [s(.running)]), st(.off, .breathe, .off)) }
    func test_waitingRunning_singleRedSteady() {
        XCTAssertEqual(iconState(for: [s(.waiting), s(.running)]), st(.steady, .off, .off))
    }
    func test_attentionRunning_singleRedBlink() {
        XCTAssertEqual(iconState(for: [s(.attention), s(.running)]), st(.blink, .off, .off))
    }
    func test_errorRunning_redBlinkPlusOrangeBreathe() {
        XCTAssertEqual(iconState(for: [s(.error), s(.running)]), st(.blink, .breathe, .off))
    }
    func test_errorOnly_redBlink()   { XCTAssertEqual(iconState(for: [s(.error)]), st(.blink, .off, .off)) }
    func test_errorIdle_redBlink_greenSuppressed() {
        XCTAssertEqual(iconState(for: [s(.error), s(.idle)]), st(.blink, .off, .off))
    }

    func test_isAnimating() {
        XCTAssertTrue(st(.blink, .off, .off).isAnimating)
        XCTAssertTrue(st(.off, .breathe, .off).isAnimating)
        XCTAssertFalse(st(.steady, .off, .steady).isAnimating)
        XCTAssertFalse(st(.off, .off, .off).isAnimating)
    }

    func test_litAlpha_offSteady() {
        XCTAssertEqual(litAlpha(for: .off, phase: 3.2), 0.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .steady, phase: 3.2), 1.0, accuracy: 0.0001)
    }
    func test_litAlpha_blink() {
        XCTAssertEqual(litAlpha(for: .blink, phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .blink, phase: 0.3), 0.2, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .blink, phase: 0.6), 1.0, accuracy: 0.0001)
    }
    func test_litAlpha_breathe() {
        XCTAssertEqual(litAlpha(for: .breathe, phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .breathe, phase: 0.75), 0.55, accuracy: 0.0001)
    }

    func test_handoffOnly_redSteady() {
        XCTAssertEqual(iconState(for: [s(.handoff)]), st(.steady, .off, .off))
    }
    func test_handoffRunning_redSteady_orangeSuppressed() {
        XCTAssertEqual(iconState(for: [s(.handoff), s(.running)]), st(.steady, .off, .off))
    }
    func test_handoffIdle_redSteady_greenSuppressed() {
        XCTAssertEqual(iconState(for: [s(.handoff), s(.idle)]), st(.steady, .off, .off))
    }
    func test_handoffAttention_redBlinkWins() {
        XCTAssertEqual(iconState(for: [s(.handoff), s(.attention)]), st(.blink, .off, .off))
    }
}
