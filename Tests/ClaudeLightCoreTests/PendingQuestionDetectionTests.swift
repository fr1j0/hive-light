import XCTest
@testable import ClaudeLightCore

final class PendingQuestionDetectionTests: XCTestCase {
    private func userPrompt(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
    }
    private func toolUse(_ name: String, id: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"\#(name)","id":"\#(id)","input":{}}]}}"#
    }
    private func toolResult(id: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(id)","content":"ok"}]}}"#
    }
    private func assistantText(_ text: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    private func askQuestions(id: String, questions: [String]) -> String {
        let qs = questions.map { #"{"question":"\#($0)"}"# }.joined(separator: ",")
        return #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","id":"\#(id)","input":{"questions":[\#(qs)]}}]}}"#
    }
    private func askSingle(id: String, question: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","id":"\#(id)","input":{"question":"\#(question)"}}]}}"#
    }

    func test_unansweredAskUserQuestion_isPending() {
        let t = [userPrompt("do the thing"),
                 toolUse("AskUserQuestion", id: "q1")].joined(separator: "\n")
        XCTAssertTrue(hasPendingUserQuestion(transcriptJSONL: t))
    }

    func test_answeredAskUserQuestion_isNotPending() {
        let t = [userPrompt("do the thing"),
                 toolUse("AskUserQuestion", id: "q1"),
                 toolResult(id: "q1"),
                 assistantText("done")].joined(separator: "\n")
        XCTAssertFalse(hasPendingUserQuestion(transcriptJSONL: t))
    }

    func test_unansweredExitPlanMode_isPending() {
        let t = [userPrompt("plan it"),
                 toolUse("ExitPlanMode", id: "p1")].joined(separator: "\n")
        XCTAssertTrue(hasPendingUserQuestion(transcriptJSONL: t))
    }

    func test_staleQuestionBeforeNewUserPrompt_isNotPending() {
        // An interrupted question turn leaves an unmatched tool_use behind;
        // a later real user prompt supersedes it.
        let t = [userPrompt("first"),
                 toolUse("AskUserQuestion", id: "q1"),
                 userPrompt("never mind, do something else"),
                 assistantText("on it")].joined(separator: "\n")
        XCTAssertFalse(hasPendingUserQuestion(transcriptJSONL: t))
    }

    func test_otherToolsPending_areNotQuestions() {
        let t = [userPrompt("go"),
                 toolUse("Bash", id: "b1")].joined(separator: "\n")
        XCTAssertFalse(hasPendingUserQuestion(transcriptJSONL: t))
    }

    func test_toolResultOnlyUserEntry_doesNotSupersede() {
        // A user entry that is purely tool_result (an answer) is not a new prompt:
        // a later question in the same turn must still count.
        let t = [userPrompt("go"),
                 toolUse("Bash", id: "b1"),
                 toolResult(id: "b1"),
                 toolUse("AskUserQuestion", id: "q1")].joined(separator: "\n")
        XCTAssertTrue(hasPendingUserQuestion(transcriptJSONL: t))
    }

    func test_emptyOrGarbage_isNotPending() {
        XCTAssertFalse(hasPendingUserQuestion(transcriptJSONL: ""))
        XCTAssertFalse(hasPendingUserQuestion(transcriptJSONL: "not json\nstill not json"))
    }

    // MARK: – Wired into the Stop action

    func test_stopAction_withPendingQuestion_isAttention() {
        let t = [userPrompt("choose"),
                 toolUse("AskUserQuestion", id: "q1")].joined(separator: "\n")
        let p = HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x", message: nil)
        XCTAssertEqual(action(for: p, transcriptJSONL: t), .set(.attention))
    }

    func test_stopAction_answeredQuestion_fallsThroughToIdle() {
        let t = [userPrompt("choose"),
                 toolUse("AskUserQuestion", id: "q1"),
                 toolResult(id: "q1"),
                 assistantText("done, merged.")].joined(separator: "\n")
        let p = HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x", message: nil)
        XCTAssertEqual(action(for: p, transcriptJSONL: t), .set(.idle))
    }

    // MARK: – pendingUserQuestionText

    func test_questionText_pendingAskUserQuestion_returnsQuestion() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Which database should we use?"])].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "Which database should we use?")
    }

    func test_questionText_singleQuestionKey_returnsQuestion() {
        let t = [userPrompt("go"),
                 askSingle(id: "q1", question: "Deploy now?")].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "Deploy now?")
    }

    func test_questionText_multipleQuestions_marksMore() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["First?", "Second?", "Third?"])].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "First? (+2 more)")
    }

    func test_questionText_answered_returnsNil() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Which?"]),
                 toolResult(id: "q1")].joined(separator: "\n")
        XCTAssertNil(pendingUserQuestionText(transcriptJSONL: t))
    }

    func test_questionText_supersededByNewPrompt_returnsNil() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Which?"]),
                 userPrompt("never mind")].joined(separator: "\n")
        XCTAssertNil(pendingUserQuestionText(transcriptJSONL: t))
    }

    func test_questionText_lastPendingWins() {
        let t = [userPrompt("go"),
                 askQuestions(id: "q1", questions: ["Old?"]),
                 askQuestions(id: "q2", questions: ["New?"])].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "New?")
    }

    func test_questionText_exitPlanMode_isFixedLabel() {
        let t = [userPrompt("plan it"),
                 toolUse("ExitPlanMode", id: "p1")].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "plan ready for review")
    }

    func test_questionText_askWithoutText_fallsBackToMarker() {
        // The existing `toolUse` fixture has empty input {}.
        let t = [userPrompt("go"),
                 toolUse("AskUserQuestion", id: "q1")].joined(separator: "\n")
        XCTAssertEqual(pendingUserQuestionText(transcriptJSONL: t), "question pending")
    }
}
