import Foundation

/// Heuristic: the assistant's final text reads as a *blocking* question awaiting
/// a reply. To avoid false "awaiting your reply" flags we require it to be a
/// concise question, not a long deliverable that merely trails off into one:
///  - ignore code (a `?` inside fenced/inline code isn't a question to the user),
///  - only flag when the remaining prose is short and ends with `?`.
public func textEndsWithQuestion(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // A long turn that happens to end with a question is a check-in, not a block.
    guard trimmed.count <= questionMaxLength else { return false }
    let prose = strippingCode(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
    return prose.last == "?"
}

/// Upper bound (characters) for treating a turn as a pending question. Tunable.
let questionMaxLength = 240

/// Remove fenced ```code``` blocks and `inline` code spans so a `?` inside code
/// isn't mistaken for a question.
func strippingCode(_ s: String) -> String {
    var t = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
    t = t.replacingOccurrences(of: "`[^`]*`", with: " ", options: .regularExpression)
    return t
}

/// Best-effort extraction of the LAST assistant message's text from a Claude Code
/// transcript (JSONL). Scans lines bottom-up; returns nil if nothing parseable.
/// Format is undocumented and may change, so this is defensive and fail-safe.
public func lastAssistantText(transcriptJSONL: String) -> String? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let message = obj["message"] as? [String: Any]
        let isAssistant = (obj["type"] as? String) == "assistant" || (message?["role"] as? String) == "assistant"
        guard isAssistant, let content = message?["content"] else { continue }
        if let s = content as? String {
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            continue
        }
        if let blocks = content as? [[String: Any]] {
            let text = blocks.filter { ($0["type"] as? String) == "text" }
                             .compactMap { $0["text"] as? String }
                             .joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
            continue   // assistant entry with no text (e.g. tool_use) -> keep scanning older entries
        }
    }
    return nil
}

/// The last sentence of the code-stripped prose — the question/ask itself,
/// for notification bodies. Nil when nothing prose-like remains.
public func finalSentence(_ text: String) -> String? {
    let prose = strippingCode(text).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prose.isEmpty else { return nil }
    let chars = Array(prose)
    var sentences: [String] = []
    var current = ""
    for (index, ch) in chars.enumerated() {
        current.append(ch)
        if ch == "." || ch == "!" || ch == "?" {
            // Only a genuine sentence boundary when the next character is
            // whitespace (or we're at the end of the text) — this keeps
            // decimals ("2.0") from splitting, and lets consecutive
            // terminators ("?!") stay in one fragment.
            let nextIndex = index + 1
            let atEnd = nextIndex >= chars.count
            let nextIsWhitespace = !atEnd && chars[nextIndex].unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
            // A "." preceded by a single lettered character that isn't itself
            // preceded by a letter (an isolated single-letter token, e.g. the
            // "g" in "e.g.") reads as an abbreviation, not a sentence end.
            let isAbbreviationPeriod: Bool
            if ch == "." && index >= 1 {
                let prevIsLetter = chars[index - 1].unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
                let prevPrevIsLetter = index >= 2 && chars[index - 2].unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
                isAbbreviationPeriod = prevIsLetter && !prevPrevIsLetter
            } else {
                isAbbreviationPeriod = false
            }
            if (atEnd || nextIsWhitespace) && !isAbbreviationPeriod {
                sentences.append(current)
                current = ""
            }
        }
    }
    if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        sentences.append(current)
    }
    // Walk back from the last fragment until one contains a letter (a
    // fragment made purely of punctuation, e.g. a stray "!" left over from
    // "?!", isn't a usable sentence on its own).
    while let candidate = sentences.last?.trimmingCharacters(in: .whitespacesAndNewlines) {
        if candidate.isEmpty {
            sentences.removeLast()
            continue
        }
        if candidate.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) {
            return candidate
        }
        sentences.removeLast()
    }
    return nil
}

/// Caps a notification detail at 140 characters (ellipsis-terminated when
/// cut) so session files stay small and banners stay readable.
public func truncatedDetail(_ text: String) -> String {
    guard text.count > 140 else { return text }
    return String(text.prefix(139)) + "…"
}
