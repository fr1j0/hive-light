import Foundation

/// Heuristic: the turn ended by handing the user a work item — a review,
/// approval, or sign-off ask — rather than a direct blocking question.
/// Evaluated on Stop only after `textEndsWithQuestion` declined, so the
/// attention heuristic keeps first claim on concise questions.
///
/// We look at the LAST prose paragraph (code stripped): a concise closer that
/// ends with `?` or contains an approval-ask phrase reads as "your move".
public func textEndsWithHandoffAsk(_ text: String) -> Bool {
    let paragraphs = strippingCode(text)
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard let closer = paragraphs.last, closer.count <= questionMaxLength else { return false }
    if closer.hasSuffix("?") { return true }
    let lowered = closer.lowercased()
    return handoffAskPhrases.contains { lowered.contains($0) }
}

/// Phrases that mark a closer as an approval ask. Tunable, like `questionMaxLength`.
private let handoffAskPhrases = [
    "please review", "let me know", "sign off", "sign-off", "approve",
    "should i proceed", "if it looks right", "if it looks good", "waiting for your",
]
