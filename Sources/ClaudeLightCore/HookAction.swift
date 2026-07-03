import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus)
    case delete
    case ignore
}

public func action(for payload: HookPayload, transcriptJSONL: String? = nil) -> HookAction {
    switch payload.hookEventName {
    case "SessionStart":
        return .set(.idle)
    case "Stop":
        if let t = transcriptJSONL {
            // Structural signal first: an unanswered AskUserQuestion/ExitPlanMode
            // is unambiguous (#56). The text heuristics remain as fallback.
            if hasPendingUserQuestion(transcriptJSONL: t) { return .set(.attention) }
            if let last = lastAssistantText(transcriptJSONL: t) {
                if textEndsWithQuestion(last) { return .set(.attention) }
                if textEndsWithHandoffAsk(last) { return .set(.handoff) }
            }
        }
        return .set(.idle)
    case "UserPromptSubmit", "PreToolUse":
        return .set(.running)
    case "Notification":
        return .set(.waiting)
    case "SessionEnd":
        return .delete
    default:
        return .ignore
    }
}
