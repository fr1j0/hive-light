import XCTest
@testable import HiveLightCore

final class ApplyHookTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hive-light-apply-\(UUID().uuidString)")
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

    private let usageTranscript =
        #"{"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":500000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0},"content":[{"type":"text","text":"x"}]}}"#

    func test_stopWithTranscript_writesContextFraction() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: usageTranscript)
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(try XCTUnwrap(s.contextFraction), 0.5, accuracy: 0.0001)
    }

    func test_transcriptlessEvent_preservesContextFraction() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: usageTranscript)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now.addingTimeInterval(1))
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(try XCTUnwrap(s.contextFraction), 0.5, accuracy: 0.0001)
    }

    func test_freshSessionWithoutTranscript_nilFraction() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        XCTAssertNil(try store.loadAll().first?.contextFraction)
    }

    // MARK: – Branch labels (#82)

    /// A minimal on-disk repo: <root>/repo/.git/HEAD on the given ref line.
    private func makeRepo(head: String) throws -> String {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("hive-light-apply-repo-\(UUID().uuidString)/repo")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try head.write(to: repo.appendingPathComponent(".git/HEAD"),
                       atomically: true, encoding: .utf8)
        return repo.path
    }

    func test_applyHook_capturesBranch_fromRepoCwd() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/feat/labels\n")
        let p = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil)
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.branch, "feat/labels")
    }

    func test_applyHook_freshReadWins_detachedClearsBranch() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/main\n")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil),
                      to: store, now: now)
        try "2e117d43b3bd541e5d5a0a77e58c2d78784ee283\n"
            .write(to: URL(fileURLWithPath: repo).appendingPathComponent(".git/HEAD"),
                   atomically: true, encoding: .utf8)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: repo, message: nil),
                      to: store, now: now)
        XCTAssertNil(try store.loadAll().first?.branch)
    }

    func test_applyHook_keepsBranch_whenPayloadHasNoCwd() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/main\n")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil),
                      to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.branch, "main")
    }

    // MARK: – Model persistence (#105)

    private let modelEntry = #"{"type":"assistant","message":{"role":"assistant","model":"claude-fable-5","usage":{"input_tokens":10}}}"#

    // MARK: repo_root — grouping identity (stable session order)

    func test_applyHook_capturesRepoRoot_andKeepsIt_withoutCwd() throws {
        let store = tempStore()
        let repo = try makeRepo(head: "ref: refs/heads/main\n")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: repo, message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.repoRoot,
                       URL(fileURLWithPath: repo).standardizedFileURL.path)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.repoRoot,
                       URL(fileURLWithPath: repo).standardizedFileURL.path)
    }

    func test_applyHook_nonRepoCwd_repoRootNil() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        XCTAssertNil(try store.loadAll().first?.repoRoot)
    }

    // MARK: started_at — set once, sticky forever (stable session order)

    func test_applyHook_setsStartedAt_onFirstWrite() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.startedAt, now)
    }

    func test_applyHook_preservesStartedAt_acrossLaterEvents() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        // Later event, different time, no cwd/transcript — startedAt sticks.
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil),
                      to: store, now: now.addingTimeInterval(600))
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.startedAt, now)
        XCTAssertEqual(s.updatedAt, now.addingTimeInterval(600))
    }

    func test_applyHook_capturesModel_fromTranscript() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil)
        try applyHook(p, to: store, now: now, transcriptJSONL: modelEntry)
        XCTAssertEqual(try store.loadAll().first?.model, "claude-fable-5")
    }

    func test_applyHook_keepsModel_whenNoTranscript() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: modelEntry)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.model, "claude-fable-5")
    }

    private let opusEntry = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":10}}}"#

    /// The freeze fix: a UserPromptSubmit that carries a transcript re-reads the
    /// model, advancing a value that a missed/raced Stop left stale — instead of
    /// keeping the old one for turns (#model-chip-refresh).
    func test_applyHook_userPromptSubmitWithTranscript_advancesStaleModel() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil),
                      to: store, now: now, transcriptJSONL: modelEntry)
        XCTAssertEqual(try store.loadAll().first?.model, "claude-fable-5")
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/x/p", message: nil),
                      to: store, now: now.addingTimeInterval(1), transcriptJSONL: opusEntry)
        XCTAssertEqual(try store.loadAll().first?.model, "claude-opus-4-8")
    }
}
