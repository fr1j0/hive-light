import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus, detail: String?)
    case delete
    case ignore
}

/// Whether an event's handling needs the transcript in hand. `Stop` has always
/// qualified (context usage + model re-read). `UserPromptSubmit` joins it so the
/// model chip and context gauge re-read at the start of each turn. `PostToolUse`
/// joins them so those values stay fresh MID-TURN — a model switch or a big
/// context jump surfaces within a tool call or two instead of freezing until the
/// turn's Stop, which matters for the long agentic turns this panel watches. The
/// original per-tool-call cost objection is obsolete: the read is 64KB-tail-
/// capped (#174), and the hook process already spawns on PostToolUse anyway, so
/// the marginal cost is one bounded read plus a reverse scan. `PreToolUse` stays
/// excluded — PostToolUse already covers the per-tool refresh.
public func eventCarriesTranscript(_ hookEventName: String) -> Bool {
    hookEventName == "Stop"
        || hookEventName == "UserPromptSubmit"
        || hookEventName == "PostToolUse"
}

public func action(for payload: HookPayload, transcriptJSONL: String? = nil) -> HookAction {
    switch payload.hookEventName {
    case "SessionStart":
        return .set(.idle, detail: nil)
    case "Stop":
        if let t = transcriptJSONL {
            // Structural signal first: an unanswered AskUserQuestion/ExitPlanMode
            // is unambiguous (#56). The text heuristics remain as fallback.
            if let question = pendingUserQuestionText(transcriptJSONL: t) {
                return .set(.attention, detail: truncatedDetail(question))
            }
            if let last = lastAssistantText(transcriptJSONL: t) {
                if textEndsWithQuestion(last) {
                    return .set(.attention, detail: finalSentence(last).map(truncatedDetail))
                }
                if textEndsWithHandoffAsk(last) {
                    return .set(.handoff, detail: finalSentence(last).map(truncatedDetail))
                }
            }
        }
        return .set(.idle, detail: nil)
    case "UserPromptSubmit", "PreToolUse":
        return .set(.running, detail: nil)
    case "PostToolUse":
        // First event after an approved tool finishes — clears a waiting red
        // that would otherwise persist until the next PreToolUse/Stop (#170).
        return .set(.running, detail: nil)
    case "Notification":
        // The payload message says what's blocked ("Claude needs your
        // permission to use Bash") — carry it into the banner (#80).
        return .set(.waiting, detail: payload.message.map(truncatedDetail))
    case "SessionEnd":
        return .delete
    default:
        return .ignore
    }
}
