import XCTest
@testable import HiveLightCore

final class QuestionDetectionTests: XCTestCase {

    // MARK: - textEndsWithQuestion

    func test_endsWithQuestion_true_plainQuestion() {
        XCTAssertTrue(textEndsWithQuestion("Which option?"))
    }

    func test_endsWithQuestion_true_trailingWhitespace() {
        XCTAssertTrue(textEndsWithQuestion("ok?\n  "))
    }

    func test_endsWithQuestion_false_period() {
        XCTAssertFalse(textEndsWithQuestion("Done."))
    }

    func test_endsWithQuestion_false_empty() {
        XCTAssertFalse(textEndsWithQuestion(""))
    }

    func test_endsWithQuestion_false_ternaryEndsWithC() {
        // "value = a ? b : c" ends with 'c', not '?'
        XCTAssertFalse(textEndsWithQuestion("value = a ? b : c"))
    }

    func test_endsWithQuestion_false_longDeliverableTrailingQuestion() {
        // A long turn that did work and merely checks in at the end is NOT a
        // blocking question — don't flag "awaiting your reply".
        let long = String(repeating: "Here is a chunk of the summary. ", count: 12) + "Want me to proceed?"
        XCTAssertFalse(textEndsWithQuestion(long))
    }

    func test_endsWithQuestion_false_questionMarkInsideCode() {
        // A `?` inside a fenced code block is not a question to the user.
        XCTAssertFalse(textEndsWithQuestion("Here is the fix:\n```\nx = a ? b : c\nprint(y?)\n```"))
    }

    func test_endsWithQuestion_true_conciseQuestionWithInlineCode() {
        XCTAssertTrue(textEndsWithQuestion("Should I run `git status` first?"))
    }

    // MARK: - lastAssistantText

    // Fixtures shaped like real Claude Code JSONL entries
    private let userLine = #"{"type":"user","message":{"role":"user","content":"hi"}}"#

    private let assistantQuestionLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Which option do you prefer?"}]}}"#

    private let assistantStatementLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"I have finished the task."}]}}"#

    private let assistantToolUseLine = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"bash","input":{}}]}}"#

    private let assistantStringContent = #"{"type":"assistant","message":{"role":"assistant","content":"Simple string answer."}}"#

    func test_lastAssistantText_returnsLastAssistantTextBlock() {
        let jsonl = [userLine, assistantQuestionLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Which option do you prefer?")
    }

    func test_lastAssistantText_skipsTrailingToolUseOnly() {
        // tool_use-only assistant entry should be skipped; returns the previous text entry
        let jsonl = [assistantQuestionLine, assistantToolUseLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Which option do you prefer?")
    }

    func test_lastAssistantText_skipsMalformedLines() {
        let jsonl = ["not-json", "{broken}", assistantStatementLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "I have finished the task.")
    }

    func test_lastAssistantText_nilOnEmpty() {
        XCTAssertNil(lastAssistantText(transcriptJSONL: ""))
    }

    func test_lastAssistantText_nilWhenOnlyUserLines() {
        XCTAssertNil(lastAssistantText(transcriptJSONL: userLine))
    }

    func test_lastAssistantText_handlesStringContent() {
        let jsonl = [assistantStringContent].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Simple string answer.")
    }

    func test_lastAssistantText_returnsLastAmongMultipleAssistant() {
        let jsonl = [assistantStatementLine, assistantQuestionLine].joined(separator: "\n")
        XCTAssertEqual(lastAssistantText(transcriptJSONL: jsonl), "Which option do you prefer?")
    }

    // MARK: - finalSentence

    func test_finalSentence_returnsLastSentence() {
        XCTAssertEqual(finalSentence("I did the thing. Should I also update the docs?"),
                       "Should I also update the docs?")
    }

    func test_finalSentence_stripsCode() {
        XCTAssertEqual(finalSentence("Run ```rm -rf tmp?``` first. Proceed?"), "Proceed?")
    }

    func test_finalSentence_singleSentence_returnsIt() {
        XCTAssertEqual(finalSentence("Deploy to production?"), "Deploy to production?")
    }

    func test_finalSentence_empty_returnsNil() {
        XCTAssertNil(finalSentence(""))
        XCTAssertNil(finalSentence("```only code```"))
    }

    func test_finalSentence_decimalNotSplit() {
        XCTAssertEqual(finalSentence("Should I bump to 2.0?"), "Should I bump to 2.0?")
    }

    func test_finalSentence_abbreviationNotSplit() {
        XCTAssertEqual(finalSentence("Should I use the CLI (e.g. Bash)?"),
                       "Should I use the CLI (e.g. Bash)?")
    }

    func test_finalSentence_consecutiveTerminators_keepFullSentence() {
        XCTAssertEqual(finalSentence("I finished. Are you sure?!"), "Are you sure?!")
    }

    func test_finalSentence_capitalOptionLabels_splitNormally() {
        XCTAssertEqual(finalSentence("Choose option A. Deploy now?"), "Deploy now?")
    }

    func test_finalSentence_letteredOptionsLongPrompt_keepsQuestion() {
        let text = "A. Deploy to staging first and run the smoke tests there. "
                 + "B. Deploy directly to production behind the feature flag. "
                 + "Which of these two approaches should I take right now?"
        XCTAssertEqual(finalSentence(text),
                       "Which of these two approaches should I take right now?")
    }

    // MARK: - truncatedDetail

    func test_truncatedDetail_shortUnchanged() {
        XCTAssertEqual(truncatedDetail("Deploy?"), "Deploy?")
    }

    func test_truncatedDetail_capsAt140WithEllipsis() {
        let long = String(repeating: "a", count: 200)
        let out = truncatedDetail(long)
        XCTAssertEqual(out.count, 140)
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func test_truncatedDetail_exactly140_unchanged() {
        let s = String(repeating: "b", count: 140)
        XCTAssertEqual(truncatedDetail(s), s)
    }
}
