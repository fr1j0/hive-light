import XCTest
@testable import HiveLightCore

final class TaskSummaryDetectionTests: XCTestCase {
    // Fixture shapes captured from a real multi-agent transcript (2026-07-17).

    /// Periodic full snapshot of the task list.
    private func reminder(_ items: [(id: String, subject: String, status: String)]) -> String {
        let content = items.map {
            #"{"id":"\#($0.id)","subject":"\#($0.subject)","activeForm":"x","status":"\#($0.status)","blocks":[],"blockedBy":[]}"#
        }.joined(separator: ",")
        return #"{"type":"attachment","attachment":{"type":"task_reminder","content":[\#(content)],"itemCount":\#(items.count)}}"#
    }
    private func emptyReminder() -> String {
        #"{"type":"attachment","attachment":{"type":"task_reminder","content":[],"itemCount":0}}"#
    }
    private func createUse(_ useID: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"\#(useID)","name":"TaskCreate","input":{"subject":"s"}}]}}"#
    }
    private func createResult(_ useID: String, taskID: String, subject: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(useID)","content":"Task #\#(taskID) created successfully: \#(subject)"}]}}"#
    }
    private func updateUse(_ taskID: String, status: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u-\#(taskID)-\#(status)","name":"TaskUpdate","input":{"taskId":"\#(taskID)","status":"\#(status)"}}]}}"#
    }
    private func join(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    func test_reminderSnapshot_summaryFromInProgress() {
        let t = reminder([("1", "Task 1: types", "completed"),
                          ("2", "Task 2: render", "in_progress"),
                          ("3", "Task 3: backfill", "pending")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 2: render", doneCount: 1, total: 3))
    }

    func test_noInProgress_returnsNil() {
        let t = reminder([("1", "Task 1", "completed"), ("2", "Task 2", "pending")])
        XCTAssertNil(taskSummary(fromTranscript: t))
    }

    func test_emptyTranscript_returnsNil() {
        XCTAssertNil(taskSummary(fromTranscript: ""))
        XCTAssertNil(taskSummary(fromTranscript: "not json\n{bad"))
    }

    func test_replayOnly_createThenUpdate_buildsSummary() {
        let t = join([createUse("c1"), createResult("c1", taskID: "1", subject: "Task 1: types"),
                      createUse("c2"), createResult("c2", taskID: "2", subject: "Task 2: render"),
                      updateUse("1", status: "in_progress"),
                      updateUse("1", status: "completed"),
                      updateUse("2", status: "in_progress")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 2: render", doneCount: 1, total: 2))
    }

    func test_updateAfterSnapshot_completingLastInProgress_returnsNil() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      updateUse("1", status: "completed")])
        XCTAssertNil(taskSummary(fromTranscript: t))
    }

    func test_createAfterSnapshot_appendsToTotal() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      createUse("c7"), createResult("c7", taskID: "7", subject: "Task 7: docs")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 1", doneCount: 0, total: 2))
    }

    func test_multipleInProgress_mostRecentlyUpdatedWins() {
        let t = join([reminder([("1", "Task 1", "in_progress"), ("2", "Task 2", "pending")]),
                      updateUse("2", status: "in_progress")])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.inProgressSubject, "Task 2")
    }

    func test_unknownTaskIdUpdate_ignored() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      updateUse("99", status: "completed")])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 1", doneCount: 0, total: 1))
    }

    func test_malformedCreateResult_ignored() {
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      createUse("c1"),
                      #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"c1","content":"something else entirely"}]}}"#])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.total, 1)
    }

    func test_emptyReminder_doesNotResetState() {
        let t = join([reminder([("1", "Task 1", "in_progress")]), emptyReminder()])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.total, 1)
    }

    func test_laterSnapshot_replacesEarlierState() {
        let t = join([reminder([("1", "Old task", "in_progress")]),
                      reminder([("1", "Task 1", "completed"), ("2", "Task 2", "in_progress")])])
        XCTAssertEqual(taskSummary(fromTranscript: t),
                       TaskSummary(inProgressSubject: "Task 2", doneCount: 1, total: 2))
    }

    func test_longSubject_truncatedTo40() {
        let long = String(repeating: "x", count: 80)
        let t = reminder([("1", long, "in_progress")])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.inProgressSubject.count, 40)
    }

    func test_nonCreateToolResult_withCreateShapedText_ignored() {
        // Only results paired to a TaskCreate tool_use count.
        let t = join([reminder([("1", "Task 1", "in_progress")]),
                      #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"bash-1","content":"Task #9 created successfully: fake"}]}}"#])
        XCTAssertEqual(taskSummary(fromTranscript: t)?.total, 1)
    }
}
