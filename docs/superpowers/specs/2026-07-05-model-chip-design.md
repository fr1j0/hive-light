# Model chip on session cards (#105)

## Goal

Each session card shows which model the session runs, as a small chip
pinned to the trailing edge of the subtitle row — branch/status text on
the left, chip on the right. User-approved in the 2026-07-05 mockup
round ("a great addition, place it to the right").

## Data flow

1. **Extraction.** The hook already loads the transcript tail on Stop
   (#96). A sibling pass lifts the last assistant entry's `model` id:
   `lastModelID(transcriptJSONL:) -> String?` — reverse line scan, same
   defensive JSONL parsing as `contextFraction`, nil when absent.
2. **Persist.** `model` key in the session JSON, merged exactly like
   `context_fraction`: refreshed when a transcript is in hand, the
   stored value survives transcript-less events. Old apps ignore the
   key; old hooks never write it (no chip).
3. **Render.** Chip at the subtitle row's trailing edge in SessionCard:
   short display name via `shortModelName(_:)` ("claude-fable-5" →
   "fable-5", "claude-haiku-4-5-20251001" → "haiku-4.5"; unknown ids
   pass through). Style: 9pt semibold, uppercase tracking, tertiary
   text on a quiet capsule (primary 9% background, 4pt radius). The
   left-side subtitle text tail-truncates; the chip never compresses
   (higher layout priority). Full raw id in the chip's `.help` tooltip;
   the card's VoiceOver label appends "model <short name>".
   No chip when `model` is nil or the card has no subtitle row.

## Edge cases

- Detached transcripts / API-error sessions: chip still renders from
  the last known model (persisted value).
- Unknown future model ids: shortened best-effort, never dropped.
- Long branch + chip on one 340pt row: branch truncates, chip holds.

## Testing

Pure Core TDD: `lastModelID` (last entry wins, non-assistant skipped,
corrupt lines skipped, missing model nil), `shortModelName` (the five
mockup cases), ApplyHook merge semantics (fresh-wins with transcript,
survives without, old JSON decodes). Chip styling is app-target glue —
full-suite regression + live verification.
