# Usage Stats — Design

## Problem

Fast models (Fable especially) burn through usage windows quickly, and limits
are tight on cheaper plans. Users want to **ration**: spend Fable on tasks that
deserve it, drop to Sonnet when the window is running hot, and know when it
resets. Claude Code's `/usage` shows this, but only inside a terminal session —
claude-light can make it a glance.

This is issue #83's third probe. The first two (worked/waited time; a header
reset countdown) were built or judged and dropped. What's different now: a
sharper job ("help me ration models"), its own toggleable space instead of
squatting in the header, and a noise filter every metric must pass.

## The noise filter

Every displayed metric must answer: **"does this help me decide whether to
spend a fast model right now?"**

Included:
- Per-model token burn in the **current 5h window** (the live rationing signal)
- Window **reset countdown** (+ wall-clock reset time in the full view)
- Per-model **daily history** (calibration aid: raw numbers gain meaning when
  you can see "yesterday: 1.7M Fable, no cutoff")

Excluded (noise, some tried-and-rejected):
- Percentages of quota — **caps are not exposed locally**; a percentage would be
  a guess dressed as a fact (established constraint from the first spike)
- Cost in dollars — plan users don't pay per token (`costUSD` is 0 in the cache)
- Worked-vs-waited time — tried, judged not relevant
- Session/message counts, lifetime totals — retrospective trivia

## Honesty stance

Burn and reset are knowable from local data; "quota left" is not. Nothing in
the UI implies capacity: the row's micro-bar shows models **relative to each
other** (composition of the window's burn), never against a limit. The full
view's footnote states this outright.

**Designed-for evolution (not built now):** learned ceiling — once a rate-limit
event is observed in a transcript, the current-window bars gain a quiet tick at
the last observed cutoff level. Measured, not assumed. The data model should
not preclude it.

## Data sources — two, with different roles

| Source | Freshness | Powers |
|---|---|---|
| Transcript scan (JSONL entry timestamps + per-entry `model` + `usage`) | live | Current window: per-model burn, reset time |
| `~/.claude/stats-cache.json` (`dailyModelTokens`), computed by Claude Code | ~daily (lags today) | Daily history in the full view |

**Token basis:** `input_tokens + output_tokens`, excluding cache reads/writes —
the same basis `dailyModelTokens` uses, so the live row and the history agree.
(Verified against the cache: daily entries are ~M-scale while lifetime
cache-read counters are ~B-scale; the cache's daily numbers are in+out.)

**Window model:** gap-aware 5h tiling. A window opens at the first activity
after the previous window closes (or the first activity ever); it closes 5h
later. "Current window" = the window containing now, if any; if the last
activity's window has closed, the row shows no burn (fresh window opens on next
activity). Reset countdown = window close − now. This mirrors Anthropic's
5h-block behavior as observable from transcripts; it was validated in the
archived quota-window spike.

## Surfaces

### 1. Usage row (variant B — micro-bar glance)

One block above the panel footer, visible only when the Settings toggle is on:

```
[####fable####|##sonnet##|#haiku#]        ← 5px composition micro-bar, 2px gaps
● FABLE 1.4M  ● SONNET 0.3M  ● HAIKU 0.1M   ↻ 1h 40m
```

- Micro-bar: one thin (5pt) stacked bar, segment widths = share of the current
  window's total burn. Rounded ends, 2pt gaps between segments.
- Chips line: color dot (6pt, 2pt radius) + model short-name (9pt semibold
  uppercase, secondary) + burn (11pt tabular, secondary), for each model active
  in the current window, in **descending-burn order** (biggest first); the
  micro-bar segments use the same order. (The daily stacks in the full view use
  *fixed* model order instead — stacked segments must keep stable order so days
  compare visually; a live composition bar reads best biggest-first.)
- Reset: `↻ 1h 40m` right-aligned, tertiary, tabular digits. The `↻` is
  rendered via SF Symbol (`arrow.trianglehead.clockwise` or nearest available)
  — **not** a raw glyph character (lesson from `⑂`).
- Model overflow: at most 3 chips + the bar; a 4th+ model folds into a grey
  `+N` chip (the bar still shows all segments).
- Empty window (no burn since last reset): the row hides entirely — no
  zero-noise.
- The whole row is a button: click flips the panel to the Usage view.
- Placement: below the session list, above the footer divider — deliberately
  far from the header, where the previous attempt died.

### 2. Usage view (dedicated pane)

Third panel state alongside the session list and Settings, using the same flip
mechanism and layout rhythm (12pt frame, 10pt gaps, 22pt content column, wide
dividers). Header: `‹ Usage` (back returns to the session list).

**Current window** section:
- One row per active model: color dot + name (52pt label column), horizontal
  bar (8pt track, filled relative to the window's max model), burn number
  (right-aligned, tabular).
- Reset line: `↻ window resets in 1h 40m · 14:00` — countdown bold, wall-clock
  tertiary.

**Daily · last 5 days** section (from `stats-cache.json`):
- One row per day: day label (`Jul 5` / `today`), stacked composition bar
  (8pt, 2pt gaps, segments in the fixed model order), total (right, tertiary).
- Bar widths scale to the max day's total in the visible range.
- `today` row: cache lags a day, so today's entry is synthesized from the live
  transcript scan (same basis) and labeled `today`; if the cache already has
  today, the live number wins.
- Hover on a bar shows exact per-model values via tooltip (`.help`).
- Legend: dot + name for every model appearing in the range (fixed order).

**Footer note** (tertiary, 10pt): "Local only — window from your transcripts,
history from Claude Code's stats cache. No caps are exposed, so bars compare
models to each other, never to a limit."

### 3. Settings toggle

`Show usage stats` checkbox with the existing toggles. **Default off** —
consistent with "Show subagents" and the routine-transitions-stay-quiet
principle. Caption under it: "Usage row in the panel · click it for details."
Persisted in `UserDefaults` like `showSubagents`.

## Model colors

Categorical palette, **fixed per model, never cycled**, validated for
colorblind separation and contrast on the dark panel surface (worst adjacent
pair ΔE 41.3; all ≥3:1 contrast):

| Model | Hex |
|---|---|
| Fable | `#3987e5` (blue) |
| Opus | `#199e70` (aqua) |
| Sonnet | `#c98500` (yellow) |
| Haiku | `#9085e9` (violet) |
| any other | grey (`Color.primary.opacity(0.35)`) |

Red/orange/green are deliberately absent — the panel reserves them for session
status. Matching uses the same family detection as `shortModelName` (substring
on the model id), so dated ids (`claude-haiku-4-5-20251001`) and bare ids
(`claude-fable-5`) both resolve. Identity is never color-alone: every dot is
adjacent to the model's name.

## Architecture

### Core (`ClaudeLightCore` — pure, tested)

- `UsageWindow.swift`:
  - `windowContaining(now:activityTimestamps:)` — gap-aware 5h tiling over
    sorted timestamps → `(start: Date, end: Date)?`
  - `usageByModel(entries:window:)` — per-model in+out token sums for entries
    inside the window, descending burn; entry = `(timestamp, model, input, output)`
    parsed from transcript JSONL (fail-safe: unparseable lines skipped)
- `StatsCache.swift`:
  - `dailyModelTokens(fromJSON:)` — tolerant decode of the cache's
    `dailyModelTokens` array → `[(date: String, tokensByModel: [String: Int])]`;
    missing file / bad JSON / unknown version → `[]`
- `UsageFormatting.swift` (or extend `PanelModel.swift`):
  - `tokenText(_:)` — `1.4M`, `320k`, `980` (one decimal above 1M, none below)
  - `resetText(until:now:)` — `1h 40m` / `40m` / `<1m`
  - `modelColorSlot(_:)` — model id → palette slot enum (`.fable/.opus/.sonnet/.haiku/.other`)

### App

- `UsageScanner` (new, off-main): async scan of live sessions' transcripts —
  reuses the existing bounded tail-read + `FileMemoCache` pattern keyed on
  `(mtime, size)`; publishes `UsageSnapshot { windowBurn: [(model, tokens)],
  windowEnd: Date?, todayBurn: [(model, tokens)] }` to the panel via the
  watcher. **The scan never runs on the main actor** — the archived attempt's
  unresolved Critical was exactly this (~200ms synchronous parse per reload).
- `UsageRow.swift` — variant B row (micro-bar + chips + reset), button → view flip.
- `UsageView.swift` — the dedicated pane (current window + daily history).
- `PanelContent.swift` — third pane state (`showingUsage`), row insertion above
  the footer, height-estimate contribution for the row (+1 unit) and the pane.
- `SettingsPane.swift` — the toggle.

### Error handling

- No transcripts / empty window → row hidden; Usage view shows the history
  sections only (or "no usage yet" if both empty).
- `stats-cache.json` missing/corrupt/renamed by a future Claude Code version →
  history section absent; current-window section unaffected. Never a crash;
  never a blocking read on the main actor.
- Model ids that match no family → grey slot, short-name via existing
  `shortModelName`.

## Testing

Pure-function tests (fixtures, no I/O):
- Window tiling: activity gaps > 5h open new windows; activity 4h59m apart
  stays in one; empty timestamps → nil window; window end = start + 5h.
- Aggregation: mixed-model entries sum in+out only (cache tokens ignored),
  descending order, entries outside the window excluded.
- Formatting: `1_400_000 → "1.4M"`, `320_000 → "320k"`, boundary `999_999`;
  reset text at 100m / 40m / 30s.
- Cache decode: real-shape fixture → rows; truncated JSON → `[]`; missing
  `dailyModelTokens` key → `[]`.
- Color slots: dated and bare ids for all four families + unknown → `.other`.

Views: live panel verification (the design gate for this project), including
the toggle default-off, row click-through, and the today row against `/usage`.

## Success criteria

The live-eval bar this must clear (the previous two attempts didn't):
1. Toggled **off**, the panel is byte-identical to today's.
2. Toggled **on**, the row reads in one glance and never pushes sessions around
   (fixed height, no reflow as numbers change).
3. The numbers are trustworthy: today's row ≈ what `/usage` implies, window
   reset time matches observed resets.
4. No perceptible reload cost (scan off-main, memoized).

## Out of scope

- Learned ceiling / cutoff ticks (designed-for, later)
- Weekly windows (Anthropic weekly caps) — revisit only if the 5h view earns
  its keep
- Any network call — local files only, per the project's privacy stance
