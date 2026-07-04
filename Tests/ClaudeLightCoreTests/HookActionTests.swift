import XCTest
@testable import ClaudeLightCore

final class HookActionTests: XCTestCase {
    private func payload(_ event: String, message: String? = nil) -> HookPayload {
        HookPayload(sessionID: "s", hookEventName: event, cwd: "/tmp/p", message: message)
    }

    func test_sessionStart_isIdle() {
        XCTAssertEqual(action(for: payload("SessionStart")), .set(.idle, detail: nil))
    }

    func test_stop_nilTranscript_isIdle() {
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: nil), .set(.idle, detail: nil))
    }

    func test_stop_questionTranscript_isAttention() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Which option?"}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl),
                       .set(.attention, detail: "Which option?"))
    }

    func test_stop_nonQuestionTranscript_isIdle() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Done."}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl), .set(.idle, detail: nil))
    }

    func test_prompt_and_preToolUse_areRunning() {
        XCTAssertEqual(action(for: payload("UserPromptSubmit")), .set(.running, detail: nil))
        XCTAssertEqual(action(for: payload("PreToolUse")), .set(.running, detail: nil))
    }

    func test_notification_anyMessage_isWaiting() {
        XCTAssertEqual(action(for: payload("Notification", message: "anything")),
                       .set(.waiting, detail: "anything"))
    }

    func test_notification_nilMessage_isWaiting() {
        XCTAssertEqual(action(for: payload("Notification")), .set(.waiting, detail: nil))
    }

    func test_sessionEnd_setsDone() {
        XCTAssertEqual(action(for: payload("SessionEnd")), .set(.done, detail: nil))
    }

    func test_unknownEvent_isIgnored() {
        XCTAssertEqual(action(for: payload("PostToolUse")), .ignore)
    }

    func test_stop_approvalProseTranscript_isHandoff() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Spec is written on the branch.\n\nPlease review — and if it looks right I'll move on to the implementation plan."}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl),
                       .set(.handoff, detail: "Please review — and if it looks right I'll move on to the implementation plan."))
    }

    func test_stop_conciseQuestion_attentionWinsOverHandoff() {
        // Ends with "?" AND contains an approval phrase; concise → attention keeps first claim.
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me know — should I proceed?"}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl),
                       .set(.attention, detail: "Let me know — should I proceed?"))
    }

    func test_stop_longTurnEndingInQuestionParagraph_isHandoff() {
        let text = String(repeating: "Here is a chunk of the summary. ", count: 12)
            + "\\n\\nShould I use approach A or B?"
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":""# + text + #""}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl),
                       .set(.handoff, detail: "Should I use approach A or B?"))
    }
}
