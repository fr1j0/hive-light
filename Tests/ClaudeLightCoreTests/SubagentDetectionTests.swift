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

    func test_doneSubagent_isShownStruck_notDropped() {
        let t = join([toolUse("t1", "done work"), toolResult("t1", isError: false)])
        let list = subagents(fromTranscript: t)
        XCTAssertEqual(list.visible, [Subagent(id: "t1", label: "done work", state: .done)])
        XCTAssertEqual(list.total, 1)
        XCTAssertEqual(list.doneCount, 1)
    }

    func test_mix_showsAllThreeStates_inDispatchOrder() {
        let t = join([
            toolUse("a", "Review Task 4"),
            toolUse("b", "Final review"), toolResult("b", isError: false),   // done
            toolUse("c", "Implement Task 5"), toolResult("c", isError: true), // failed
        ])
        let list = subagents(fromTranscript: t)
        XCTAssertEqual(list.visible, [
            Subagent(id: "a", label: "Review Task 4", state: .running),
            Subagent(id: "b", label: "Final review", state: .done),
            Subagent(id: "c", label: "Implement Task 5", state: .failed),
        ])
        XCTAssertEqual(list.total, 3)
        XCTAssertEqual(list.doneCount, 1)
        XCTAssertEqual(list.failedCount, 1)
    }

    func test_doneSubagent_supersededByLaterUserPrompt_isCleared() {
        let t = join([toolUse("t1", "old batch"), toolResult("t1", isError: false),
                      userPrompt("continue")])
        let list = subagents(fromTranscript: t)
        XCTAssertTrue(list.isEmpty)
        XCTAssertEqual(list.total, 0)
    }

    func test_denominator_resetsToNewBatchAfterPrompt() {
        // Old batch of 2 (both done) settled before the prompt; new batch of 3
        // dispatched after → count reflects only the new batch.
        let t = join([
            toolUse("o1", "old 1"), toolResult("o1", isError: false),
            toolUse("o2", "old 2"), toolResult("o2", isError: false),
            userPrompt("next"),
            toolUse("n1", "new 1"), toolResult("n1", isError: false),
            toolUse("n2", "new 2"),
            toolUse("n3", "new 3"),
        ])
        let list = subagents(fromTranscript: t)
        XCTAssertEqual(list.total, 3)
        XCTAssertEqual(list.doneCount, 1)
        XCTAssertEqual(list.visible.map(\.id), ["n1", "n2", "n3"])
    }

    func test_rowCap_keepsFailedAndRunning_collapsesDoneTail() {
        // 1 failed + 2 running + 7 done, cap 6 → 1+2+3 = 6 rows, +4 done overflow.
        var lines = [toolUse("f", "fail"), toolResult("f", isError: true),
                     toolUse("r1", "run 1"), toolUse("r2", "run 2")]
        for i in 1...7 { lines += [toolUse("d\(i)", "done \(i)"), toolResult("d\(i)", isError: false)] }
        let list = subagents(fromTranscript: join(lines), maxRows: 6)
        XCTAssertEqual(list.visible.count, 6)
        XCTAssertEqual(list.overflowDone, 4)
        XCTAssertEqual(list.overflowRunning, 0)
        XCTAssertEqual(list.total, 10)
        XCTAssertEqual(list.doneCount, 7)
        XCTAssertEqual(list.failedCount, 1)
        // Failed + both running always survive the cap.
        XCTAssertEqual(list.visible.filter { $0.state == .failed }.count, 1)
        XCTAssertEqual(list.visible.filter { $0.state == .running }.count, 2)
        XCTAssertEqual(list.visible.filter { $0.state == .done }.count, 3)
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

    func test_runningCap_capsAtMaxRows_withOverflowCount() {
        let lines = (1...8).map { toolUse("r\($0)", "subagent \($0)") }
        let list = subagents(fromTranscript: join(lines), maxRows: 5)
        XCTAssertEqual(list.visible.count, 5)
        XCTAssertEqual(list.overflowRunning, 3)
        XCTAssertEqual(list.visible.map(\.id), ["r1", "r2", "r3", "r4", "r5"])
        XCTAssertEqual(list.total, 8)
    }

    func test_failedNotCapped_alwaysShown() {
        // 6 failed with cap 5 → all failed still visible (never dropped), no overflow.
        let lines = (1...6).flatMap { [toolUse("f\($0)", "f\($0)"), toolResult("f\($0)", isError: true)] }
        let list = subagents(fromTranscript: join(lines), maxRows: 5)
        XCTAssertEqual(list.visible.count, 6)
        XCTAssertEqual(list.failedCount, 6)
        XCTAssertEqual(list.overflowRunning, 0)
        XCTAssertEqual(list.overflowDone, 0)
    }

    func test_bothRunningAndDoneOverflow_inOneBatch() {
        var lines = (1...8).map { toolUse("r\($0)", "run \($0)") }
        for i in 1...3 { lines += [toolUse("d\(i)", "done \(i)"), toolResult("d\(i)", isError: false)] }
        let list = subagents(fromTranscript: join(lines), maxRows: 6)
        XCTAssertEqual(list.visible.count, 6)
        XCTAssertEqual(list.visible.allSatisfy { $0.state == .running }, true)
        XCTAssertEqual(list.overflowRunning, 2)
        XCTAssertEqual(list.overflowDone, 3)
        XCTAssertEqual(list.total, 11)
        XCTAssertEqual(list.doneCount, 3)
        XCTAssertEqual(list.failedCount, 0)
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
