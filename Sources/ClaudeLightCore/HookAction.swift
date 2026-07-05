import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus, detail: String?)
    case delete
    case ignore
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
