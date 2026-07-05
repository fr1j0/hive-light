# Context-usage gauge on session cards (#96)

## Problem

"How much runway does this agent have before auto-compact?" currently
requires switching to each terminal and running `/context`. For long,
concurrent sessions that is exactly the glance the panel exists to save.

## Goal

Five segment ticks beside each card's timer showing context-window usage:
grey while comfortable, orange past 75%, red past 90%. No number — the
ticks and color carry the signal; the exact percentage lives in a hover
tooltip. Validated via mockups (segments chosen over inline text and over
a full-width bar, which reads as task progress under a working card).

## Design

### Extraction (hook side, Stop events)

- New pure Core function
  `contextFraction(transcriptJSONL: String) -> Double?`:
  scan lines bottom-up for the last assistant entry carrying a
  `message.usage` dictionary; context tokens =
  `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
  (missing keys count 0). Model string from the same entry's
  `message.model`. Returns `min(tokens / window, 1.0)`, nil when no
  usage entry parses (fail-safe, like all transcript parsing).
- Window map: model id containing `"[1m]"` or `"-1m"` → 1_000_000,
  otherwise 200_000. Conservative default; unknown models read slightly
  hot rather than slightly safe.
- Runs where the transcript is already in hand: the hook's Stop path
  (same tail read that powers question detection — no new I/O, #43
  budget untouched). The gauge therefore updates at turn boundaries.

### Schema & persistence

- `Session` gains `contextFraction: Double?` (JSON key
  `context_fraction`), last init parameter, default nil.
- `applyHook` computes it from the provided transcript when present;
  when absent (UserPromptSubmit, PreToolUse, Notification), it merges
  the existing session's value — like terminal identity, NOT like
  `detail` — so frequent non-Stop events don't blank the gauge.
  SessionEnd deletes the file as usual.
- Compatibility: old app ignores the unknown key; old hook leaves it
  nil → no ticks rendered. No migration.

### Display

- PanelModel pure helpers:
  - `contextSegments(fraction: Double) -> Int` — lit ticks out of 5,
    `Int((fraction * 5).rounded(.up))` clamped 1...5 (any measured
    usage lights at least one tick).
  - `contextLevel(fraction: Double) -> ContextLevel` — enum
    `ok` (< 0.75) / `warm` (0.75..<0.9) / `hot` (>= 0.9).
  - `contextTooltip(fraction: Double) -> String` —
    `"context NN% used"` (percentage rounded to whole).
- `SessionCard` meta area: the five-tick view sits before the timer,
  only when `session.contextFraction != nil`. Tick colors: lit ticks
  grey (`.ok`), orange (`.warm` — PanelPalette.orange), red (`.hot` —
  PanelPalette.red); unlit ticks a faint neutral. `.help(tooltip)` on
  the tick group. Tick geometry ≈ 4×7pt, 1.5pt gaps.
- No change to notifications, sorting, or the aggregate light — the
  gauge is passive information (exceptional-events principle: color
  escalates, nothing pings).

## Testing

TDD in Core:

- `contextFraction`: parses usage with all three token fields; missing
  cache fields count 0; last assistant entry wins; garbage lines
  skipped; nil on no usage; 1M window for `[1m]` model ids; clamped at
  1.0.
- `applyHook`: Stop with transcript writes the fraction; a following
  PreToolUse without transcript preserves it; fresh session without
  transcript stays nil.
- Segment math: boundaries — 0.01→1 tick ok; 0.46→3 ticks ok;
  0.75→4 ticks warm; 0.9→5 hot; 1.0→5 hot. Tooltip wording.

App side: build + e2e (fake sessions with fractions across the three
levels; hover tooltip; live session gains ticks after its next Stop).

## Out of scope

- Per-turn (PreToolUse-time) updates — Stop-boundary freshness only.
- Any notification or light change from context pressure.
- Surfacing raw token counts anywhere but the tooltip's percentage.
