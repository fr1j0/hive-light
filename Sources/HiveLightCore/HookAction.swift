import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus, detail: String?)
    case delete
    case ignore
}

/// Whether an event's handling needs the transcript in hand — the expensive
/// read is worth it only here. `Stop` has always qualified (context usage +
/// model re-read). `UserPromptSubmit` joins it so the model chip and context
/// gauge re-read once at the start of each turn, self-healing a value frozen on
/// a missed or raced Stop instead of staying stale for turns. `PreToolUse` is
/// deliberately excluded: it fires per tool call and a full read each time is
/// too costly, so it keeps the last measurement.
public func eventCarriesTranscript(_ hookEventName: String) -> Bool {
    hookEventName == "Stop" || hookEventName == "UserPromptSubmit"
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
