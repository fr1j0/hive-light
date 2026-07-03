import XCTest
@testable import ClaudeLightCore

final class TerminalContextTests: XCTestCase {
    func test_readsTermProgramAndTTY() {
        let ctx = TerminalContext(environment: ["TERM_PROGRAM": "iTerm.app"], tty: "ttys003")
        XCTAssertEqual(ctx.termProgram, "iTerm.app")
        XCTAssertEqual(ctx.tty, "ttys003")
    }

    func test_emptyOrWhitespaceTTY_isNil() {
        XCTAssertNil(TerminalContext(environment: [:], tty: "").tty)
        XCTAssertNil(TerminalContext(environment: [:], tty: "   ").tty)
        XCTAssertNil(TerminalContext(environment: [:], tty: nil).tty)
    }

    func test_prefersITermSessionId_thenTerminal_thenWarp() {
        let iterm = TerminalContext(environment: [
            "ITERM_SESSION_ID": "w0t1p0:UUID", "TERM_SESSION_ID": "x", "WARP_SESSION_ID": "y",
        ], tty: nil)
        XCTAssertEqual(iterm.termSessionId, "w0t1p0:UUID")

        let warp = TerminalContext(environment: ["WARP_SESSION_ID": "wsid"], tty: nil)
        XCTAssertEqual(warp.termSessionId, "wsid")
    }

    func test_missingKeys_areNil() {
        let ctx = TerminalContext(environment: [:], tty: nil)
        XCTAssertNil(ctx.termProgram)
        XCTAssertNil(ctx.termSessionId)
        XCTAssertNil(ctx.focusURL)
    }

    // MARK: – WARP_FOCUS_URL (#62)

    func test_capturesWarpFocusURL() {
        let ctx = TerminalContext(environment: [
            "TERM_PROGRAM": "WarpTerminal",
            "WARP_FOCUS_URL": "warp://session/c175d2a4cd8c4408b05a96bf615530d2",
        ], tty: nil)
        XCTAssertEqual(ctx.focusURL, "warp://session/c175d2a4cd8c4408b05a96bf615530d2")
    }

    func test_rejectsNonWarpFocusURL() {
        let https = TerminalContext(environment: ["WARP_FOCUS_URL": "https://evil.example/x"], tty: nil)
        XCTAssertNil(https.focusURL, "only warp:// URLs may be stored — the value is opened on click")
        let blank = TerminalContext(environment: ["WARP_FOCUS_URL": "  "], tty: nil)
        XCTAssertNil(blank.focusURL)
    }
}
