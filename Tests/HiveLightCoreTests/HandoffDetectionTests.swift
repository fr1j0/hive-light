import XCTest
@testable import HiveLightCore

final class HandoffDetectionTests: XCTestCase {

    // The motivating case: a long deliverable turn ending in an approval ask,
    // no question mark anywhere.
    private let motivatingTurn = """
    The five surfaces are covered and the spec documents the three decisions \
    taken while you were away.

    Spec is at docs/specs/design.md and the branch is created and ready.

    Please review — especially the three flagged decisions — and if it looks \
    right I'll move on to the implementation plan.
    """

    func test_true_approvalPhraseInTrailingParagraph() {
        XCTAssertTrue(textEndsWithHandoffAsk(motivatingTurn))
    }

    func test_true_longTurnWhoseTrailingParagraphEndsWithQuestionMark() {
        let long = String(repeating: "Here is a chunk of the summary. ", count: 12)
            + "\n\nShould I use approach A or B for the migration?"
        XCTAssertTrue(textEndsWithHandoffAsk(long))
    }

    func test_true_caseInsensitivePhrase() {
        XCTAssertTrue(textEndsWithHandoffAsk("Work is done.\n\nPLEASE REVIEW the spec."))
    }

    func test_false_questionMarkOnlyInsideCode() {
        XCTAssertFalse(textEndsWithHandoffAsk("Here is the fix:\n\n```\nx = a ? b : c\nprint(y?)\n```"))
    }

    func test_false_trailingParagraphTooLong() {
        let bloated = "Intro paragraph.\n\n"
            + String(repeating: "please review this endless wall of text ", count: 10) + "?"
        XCTAssertFalse(textEndsWithHandoffAsk(bloated))
    }

    func test_false_plainCompletion() {
        XCTAssertFalse(textEndsWithHandoffAsk("All 131 tests pass."))
    }

    func test_false_empty() {
        XCTAssertFalse(textEndsWithHandoffAsk(""))
    }
}
