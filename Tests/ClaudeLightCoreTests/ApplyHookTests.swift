import XCTest
@testable import ClaudeLightCore

final class ApplyHookTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-apply-\(UUID().uuidString)")
        return SessionStore(directory: dir)
    }

    private let now = Date(timeIntervalSince1970: 1_719_745_200)

    func test_setAction_writesSession_withProjectFromCwd() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/Users/x/vatios", message: nil)
        try applyHook(p, to: store, now: now)
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(s.project, "vatios")
        XCTAssertEqual(s.updatedAt, now)
    }

    func test_ignoreAction_writesNothing() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "PostToolUse", cwd: "/x", message: nil)
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_sessionEnd_removesSession() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil), to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "SessionEnd", cwd: nil, message: nil), to: store, now: now)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_missingCwd_projectIsUnknown() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil), to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.project, "unknown")
    }

    func test_applyHook_persistsTerminalContext() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil)
        let terminal = TerminalContext(termProgram: "iTerm.app", tty: "ttys004", termSessionId: "w0t1p0:UUID")
        try applyHook(p, to: store, now: now, terminal: terminal)
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.termProgram, "iTerm.app")
        XCTAssertEqual(s.tty, "ttys004")
        XCTAssertEqual(s.termSessionId, "w0t1p0:UUID")
    }

    // MARK: – Terminal identity is captured once and preserved (#42)

    func test_applyHook_preservesExistingTerminal_whenLaterEventHasNone() throws {
        let store = tempStore()
        let first = HookPayload(sessionID: "s1", hookEventName: "SessionStart", cwd: "/x/p", message: nil)
        let terminal = TerminalContext(termProgram: "iTerm.app", tty: "ttys004", termSessionId: "w0t1p0:UUID")
        try applyHook(first, to: store, now: now, terminal: terminal)

        let later = HookPayload(sessionID: "s1", hookEventName: "PreToolUse", cwd: "/x/p", message: nil)
        try applyHook(later, to: store, now: now.addingTimeInterval(5), terminal: nil)

        let s = try XCTUnwrap(store.load(sessionID: "s1"))
        XCTAssertEqual(s.termProgram, "iTerm.app")
        XCTAssertEqual(s.tty, "ttys004")
        XCTAssertEqual(s.termSessionId, "w0t1p0:UUID")
    }

    func test_applyHook_keepsFirstTTY_overLaterDifferentOne() throws {
        let store = tempStore()
        let first = HookPayload(sessionID: "s1", hookEventName: "SessionStart", cwd: "/x/p", message: nil)
        try applyHook(first, to: store, now: now,
                      terminal: TerminalContext(termProgram: "iTerm.app", tty: "ttys004", termSessionId: nil))
        let later = HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil)
        try applyHook(later, to: store, now: now.addingTimeInterval(5),
                      terminal: TerminalContext(termProgram: "iTerm.app", tty: "ttys009", termSessionId: nil))
        XCTAssertEqual(store.load(sessionID: "s1")?.tty, "ttys004")
    }

    func test_applyHook_fillsTerminal_whenExistingLacksIt() throws {
        let store = tempStore()
        let first = HookPayload(sessionID: "s1", hookEventName: "SessionStart", cwd: "/x/p", message: nil)
        try applyHook(first, to: store, now: now, terminal: nil)
        let later = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil)
        try applyHook(later, to: store, now: now.addingTimeInterval(5),
                      terminal: TerminalContext(termProgram: "Apple_Terminal", tty: "ttys002", termSessionId: "T1"))
        let s = try XCTUnwrap(store.load(sessionID: "s1"))
        XCTAssertEqual(s.termProgram, "Apple_Terminal")
        XCTAssertEqual(s.tty, "ttys002")
        XCTAssertEqual(s.termSessionId, "T1")
    }

    // MARK: – Warp focus URL persisted and preserved-first (#62)

    func test_applyHook_persistsAndPreservesFocusURL() throws {
        let store = tempStore()
        let first = HookPayload(sessionID: "s1", hookEventName: "SessionStart", cwd: "/x/p", message: nil)
        try applyHook(first, to: store, now: now,
                      terminal: TerminalContext(termProgram: "WarpTerminal", tty: nil,
                                                termSessionId: nil, focusURL: "warp://session/abc"))
        let later = HookPayload(sessionID: "s1", hookEventName: "PreToolUse", cwd: "/x/p", message: nil)
        try applyHook(later, to: store, now: now.addingTimeInterval(5), terminal: nil)
        XCTAssertEqual(store.load(sessionID: "s1")?.focusURL, "warp://session/abc")
    }

    func test_applyHook_persistsTranscriptPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = HookPayload(sessionID: "s1", hookEventName: "PreToolUse", cwd: "/Users/me/proj",
                                  message: nil, transcriptPath: "/Users/me/.claude/projects/p/s1.jsonl")
        try applyHook(payload, to: store, now: Date(timeIntervalSince1970: 1000))
        let stored = try store.loadAll().first { $0.sessionID == "s1" }
        XCTAssertEqual(stored?.transcriptPath, "/Users/me/.claude/projects/p/s1.jsonl")
    }

    func test_notificationDetail_isWrittenToSession() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "Notification", cwd: "/x/p",
                            message: "Claude needs your permission to use Bash")
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.detail,
                       "Claude needs your permission to use Bash")
    }

    func test_runningWrite_clearsStaleDetail() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Notification", cwd: "/x/p",
                                  message: "permission?"), to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p",
                                  message: nil), to: store, now: now.addingTimeInterval(1))
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertNil(s.detail)
    }
}
