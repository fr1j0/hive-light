import XCTest
@testable import ClaudeLightCore

final class SubagentDetectionTests: XCTestCase {
    // A parallel dispatch is a `Task`/`Agent` tool_use in the parent transcript.
    private func toolUse(_ id: String, _ description: String, name: String = "Task") -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":{"description":"\#(description)"}}]}}"#
    }
    private func toolResult(_ id: String, isError: Bool) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","is_error":\#(isError),"content":"x"}]}}"#
    }
    private func join(_ lines: [String]) -> String { lines.joined(separator: "\n") }


    private func userPrompt(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
    }

    func test_failedSubagent_supersededByLaterUserPrompt_isDropped() {
        let t = join([toolUse("t1", "Fix final-review findings"),
                      toolResult("t1", isError: true),
                      userPrompt("continue")])
        XCTAssertTrue(subagents(fromTranscript: t).visible.isEmpty)
    }

    func test_failedSubagent_withNoLaterPrompt_staysVisible() {
        let t = join([userPrompt("do the thing"),
                      toolUse("t1", "verify build"),
                      toolResult("t1", isError: true)])
        XCTAssertEqual(subagents(fromTranscript: t).visible,
                       [Subagent(id: "t1", label: "verify build", state: .failed)])
    }

    func test_runningSubagent_survivesLaterUserPrompt() {
        // A queued user message can land while a foreground fan-out is still
        // in flight — running entries must not be superseded.
        let t = join([toolUse("t1", "long worker"),
                      userPrompt("status?")])
        XCTAssertEqual(subagents(fromTranscript: t).visible,
                       [Subagent(id: "t1", label: "long worker", state: .running)])
    }

    func test_toolUseWithNoResult_isRunning() {
        let t = toolUse("t1", "Review Task 4")
        let list = subagents(fromTranscript: t)
        XCTAssertEqual(list.visible, [Subagent(id: "t1", label: "Review Task 4", state: .running)])
        XCTAssertEqual(list.overflowRunning, 0)
    }

    func test_toolResultIsErrorTrue_isFailed() {
        let t = join([toolUse("t1", "Implement Task 5"), toolResult("t1", isError: true)])
        XCTAssertEqual(subagents(fromTranscript: t).visible,
                       [Subagent(id: "t1", label: "Implement Task 5", state: .failed)])
    }

    func test_toolResultIsErrorFalse_isDone_andHidden() {
        let t = join([toolUse("t1", "done work"), toolResult("t1", isError: false)])
        XCTAssertTrue(subagents(fromTranscript: t).visible.isEmpty)
    }

    func test_mix_showsRunningAndFailed_hidesDone_preservesOrder() {
        let t = join([
            toolUse("a", "Review Task 4"),
            toolUse("b", "Final review"), toolResult("b", isError: false),  // done → hidden
            toolUse("c", "Implement Task 5"), toolResult("c", isError: true), // failed
        ])
        XCTAssertEqual(subagents(fromTranscript: t).visible, [
            Subagent(id: "a", label: "Review Task 4", state: .running),
            Subagent(id: "c", label: "Implement Task 5", state: .failed),
        ])
    }

    func test_agentToolUse_isAlsoRecognized() {
        let t = toolUse("t1", "web search", name: "Agent")
        XCTAssertEqual(subagents(fromTranscript: t).visible,
                       [Subagent(id: "t1", label: "web search", state: .running)])
    }

    func test_nonSubagentToolUse_ignored() {
        let bash = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"ls"}}]}}"#
        XCTAssertTrue(subagents(fromTranscript: bash).visible.isEmpty)
    }

    func test_runningCap_capsAtMaxActive_withOverflowCount() {
        let lines = (1...8).map { toolUse("r\($0)", "subagent \($0)") }
        let list = subagents(fromTranscript: join(lines), maxActive: 5)
        XCTAssertEqual(list.visible.count, 5)
        XCTAssertEqual(list.overflowRunning, 3)
        XCTAssertEqual(list.visible.map(\.id), ["r1", "r2", "r3", "r4", "r5"])
    }

    func test_failedNotCapped_alwaysShown() {
        // 6 failed subagents with maxActive 5 → all failed still visible, no overflow.
        let lines = (1...6).flatMap { [toolUse("f\($0)", "f\($0)"), toolResult("f\($0)", isError: true)] }
        let list = subagents(fromTranscript: join(lines), maxActive: 5)
        XCTAssertEqual(list.visible.count, 6)
        XCTAssertEqual(list.overflowRunning, 0)
    }

    func test_longDescription_isTruncated() {
        let long = String(repeating: "x", count: 80)
        let label = subagents(fromTranscript: toolUse("t1", long)).visible.first?.label ?? ""
        XCTAssertLessThanOrEqual(label.count, 40)
    }

    func test_garbageAndEmpty_isEmptyNoCrash() {
        XCTAssertTrue(subagents(fromTranscript: "").visible.isEmpty)
        XCTAssertTrue(subagents(fromTranscript: "not json\n{bad").visible.isEmpty)
    }
}
