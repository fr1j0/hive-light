# Pending question in the needs-you notification (#80)

## Problem

The needs-you notification says only "awaiting your reply" / "waiting for
permission". The informative text exists but is dropped at two points: the
`Notification` hook event's `message` ("Claude needs your permission to use
Bash") is discarded in `HookAction`, and the question detection (#56)
returns only a boolean — the question text never leaves the transcript. One
glance at the banner should decide "urgent or can wait".

## Design

### Approach: hook-side extraction into the session file (chosen)

At status-write time the hook extracts a short `detail` string and stores
it in the session JSON. The app's notification body becomes
`detail ?? friendlyStatusLabel`. Chosen because it is the only approach
that can cover permission prompts (the `message` exists only in the hook
payload), it matches the architecture (hook computes, file carries, app
displays), and it adds no transcript reads.

Rejected: app-side extraction at notification time (duplicates detection,
re-reads transcripts, structurally cannot see the permission message);
structural-only extraction (skips heuristic questions and permission
prompts for barely less work).

### Schema

- `Session` gains `detail: String?` (JSON key `detail`), defaulting to nil
  in the memberwise init so existing call sites compile unchanged.
- Set only when the written status is a needs-you one with extractable
  text; nil otherwise. `applyHook` rebuilds the struct on every event, so
  a running/idle write clears a stale detail naturally.
- Compatibility: the old app ignores the unknown key (Codable); an old
  hook leaves it nil and the app falls back to today's label. No
  migration.

### Extraction, per status

`HookAction.action(for:)` currently returns `.set(SessionStatus)`; it
gains the detail alongside the status — `.set` becomes
`case set(SessionStatus, detail: String?)`. Swift enum cases can't take
default associated values, so every construction and pattern match is
updated mechanically (`.set(.idle)` → `.set(.idle, detail: nil)`; the
`applyHook` match binds both).

- `.waiting` — the `Notification` payload's `message`, verbatim.
- `.attention` (structural, #56) — the question text of the *last still-
  pending* blocking tool_use: `AskUserQuestion` → its `input.question`
  string; `ExitPlanMode` → the fixed string `"plan ready for review"`.
  `hasPendingUserQuestion` is superseded by a new
  `pendingUserQuestionText(transcriptJSONL:) -> String?` returning nil
  when nothing is pending (same supersede-on-new-prompt semantics; the
  boolean callers become `!= nil`).
- `.attention` (heuristic) / `.handoff` — the final sentence of
  `lastAssistantText` (new helper `finalSentence(_:) -> String?`:
  code-stripped, whitespace-trimmed, last sentence-terminated fragment).
- All details pass through `truncatedDetail(_:) -> String` capping at 140
  characters with a trailing ellipsis, applied at extraction so session
  files stay small and hook perf (#43) is untouched.

### Display

`SessionWatcher.reload()`'s notification body:

- error: unchanged (`"API error: …"`).
- otherwise: `session.detail ?? friendlyStatusLabel(for: session.status)`.

Menu rows are deliberately unchanged — row-level context is #81.

### Testing

TDD in Core:

- `pendingUserQuestionText`: returns the question of a pending
  AskUserQuestion; nil after a tool_result answers it; nil after a newer
  real user prompt; ExitPlanMode → "plan ready for review"; last pending
  wins when several are open.
- `finalSentence`: multi-sentence text → last sentence; code blocks
  stripped; nil on empty.
- `truncatedDetail`: short strings unchanged; long strings cut at 140
  with ellipsis.
- `action(for:)`: Notification event carries payload message as detail;
  Stop + structural question carries the question text; Stop + heuristic
  question carries the final sentence; running/idle writes carry nil.
- `applyHook`: detail lands in the written session; a later running write
  clears it.

App wiring is a one-line body change, covered by build + existing
notification behavior.

## Out of scope

- Showing `detail` in menu rows (#81) or anywhere but the notification.
- Any new notification triggers (notifications stay exceptional-only).
