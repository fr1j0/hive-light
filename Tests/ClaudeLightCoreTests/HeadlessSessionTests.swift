import XCTest
@testable import ClaudeLightCore

final class HeadlessSessionTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus,
                         tty: String? = nil, focusURL: String? = nil,
                         termProgram: String? = nil) -> Session {
        Session(sessionID: id, status: status, project: "p", cwd: "/x/p",
                updatedAt: Date(timeIntervalSince1970: 1_719_745_200),
                termProgram: termProgram, tty: tty, focusURL: focusURL)
    }

    // MARK: – isHeadless (#64)

    func test_headless_whenNoTTYAndNoFocusURL() {
        XCTAssertTrue(isHeadless(session("a", .idle)))
    }

    func test_headless_evenWithInheritedTermProgram() {
        // Child processes inherit TERM_PROGRAM from the spawning shell, so it
        // must not count as terminal identity.
        XCTAssertTrue(isHeadless(session("a", .idle, termProgram: "WarpTerminal")))
    }

    func test_notHeadless_withTTY() {
        XCTAssertFalse(isHeadless(session("a", .idle, tty: "ttys006")))
    }

    func test_notHeadless_withFocusURL() {
        XCTAssertFalse(isHeadless(session("a", .idle, focusURL: "warp://session/abc")))
    }

    // MARK: – visibleSessions

    func test_idleHeadless_isHidden() {
        let out = visibleSessions([session("a", .idle)])
        XCTAssertTrue(out.isEmpty)
    }

    func test_runningHeadless_staysVisible() {
        XCTAssertEqual(visibleSessions([session("a", .running)]).count, 1)
    }

    func test_needsYouHeadless_staysVisible() {
        XCTAssertEqual(visibleSessions([session("a", .attention)]).count, 1)
    }

    func test_idleWithTerminal_staysVisible() {
        XCTAssertEqual(visibleSessions([session("a", .idle, tty: "ttys000")]).count, 1)
    }


    // MARK: – displayName

    func test_displayName_marksHeadlessAsBackground() {
        XCTAssertEqual(displayName(for: session("a", .running)), "p (background)")
    }

    func test_displayName_plainForTerminalSessions() {
        XCTAssertEqual(displayName(for: session("a", .running, tty: "ttys006")), "p")
    }
}
