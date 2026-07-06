import XCTest
@testable import ClaudeLightCore

final class HeadlessSessionTests: XCTestCase {
    private func session(_ id: String, _ status: SessionStatus,
                         tty: String? = nil, focusURL: String? = nil,
                         termProgram: String? = nil, cwd: String = "/x/p") -> Session {
        Session(sessionID: id, status: status, project: "p", cwd: cwd,
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

    // MARK: – temp-dir sessions (machinery, not work)

    func test_tempDir_allFourRootsMatch() {
        XCTAssertTrue(isTempDirSession(cwd: "/tmp/x"))
        XCTAssertTrue(isTempDirSession(cwd: "/private/tmp/x"))
        XCTAssertTrue(isTempDirSession(cwd: "/var/folders/b1/8gtjt5f56xl2/T"))
        XCTAssertTrue(isTempDirSession(cwd: "/private/var/folders/b1/8gtjt5f56xl2/T"))
    }

    func test_tempDir_projectAndWorktreePathsDontMatch() {
        XCTAssertFalse(isTempDirSession(cwd: "/Users/f/Projects/claude-light"))
        XCTAssertFalse(isTempDirSession(cwd: "/Users/f/Projects/x/.claude/worktrees/y"))
        XCTAssertFalse(isTempDirSession(cwd: "/Users/f/tmp/notes"))   // not a system root
        XCTAssertFalse(isTempDirSession(cwd: ""))
    }

    func test_visibleSessions_dropsTempDirSessions_evenRunning() {
        let tempRunning = session("t1", .running, cwd: "/private/var/folders/b1/x/T")
        let tempIdle = session("t2", .idle, cwd: "/tmp/x")
        let real = session("r", .running, tty: "ttys001")
        XCTAssertEqual(visibleSessions([tempRunning, tempIdle, real]).map(\.sessionID), ["r"])
    }

    func test_visibleSessions_keepsRunningHeadless_inProjectDirs() {
        // The #64 judgment stands for real project dirs: a live headless job shows.
        let bg = session("bg", .running)   // headless, cwd /x/p
        XCTAssertEqual(visibleSessions([bg]).map(\.sessionID), ["bg"])
    }
}
