# Quota window in the panel header (#83)

## Goal

The panel's header summary line gains a right-aligned reset countdown —
"↻ 2h 10m" — showing when the current 5-hour usage window resets. The
hover tooltip carries the detail: "2.4M tokens since 12:00 across 3
sessions · resets at 17:00 · models: fable-5, sonnet-5". Nothing else
changes: no new rows, no charts (mockup round rejected four strip
variants; the header treatment won).

Scope pivot, recorded on the issue: the original worked/waited time
mirror was judged not relevant. The per-session model chip split into
its own ticket (#105).

## Data source: transcripts, not a new log

Claude Code's transcripts (`~/.claude/projects/*/*.jsonl`) already
persist every assistant entry with its `model`, full `usage` breakdown,
and ISO8601 `timestamp` — verified live. They outlive app restarts and
accrue while the menu-bar app is closed, so they ARE the durable usage
history. The app derives the window read-side; the hook writes nothing
new (the earlier hook-writes-stats.jsonl sketch died with the pivot).

## Window model

Subscription limits reset on 5-hour blocks anchored to first activity:

- Collect assistant-entry timestamps from transcripts modified within
  the last 6 hours (5h window + 1h margin), across ALL projects.
- The anchor is the first entry after the most recent gap of ≥ 5 hours
  between consecutive entries (or the earliest entry seen). Blocks tile
  forward from the anchor in 5-hour steps: the current block starts at
  `anchor + 5h × floor((now − anchor) / 5h)` and resets 5 hours after
  that. Only entries inside the current block count toward its totals.
  If the newest entry is older than 5 hours, there is no active window.
- Tokens counted per entry: `input_tokens + cache_creation_input_tokens
  + output_tokens`. Cache reads are excluded — they dominate raw counts
  (tens of k per turn) while being the cheapest, least quota-correlated
  component. Assumption, labeled as such: Anthropic's exact limit
  weighting is not public; this sum tracks it directionally. The
  tooltip says "tokens", never a percentage — the plan's cap is not
  exposed locally, and a made-up denominator is worse than none.
- Models: distinct `model` ids among current-window entries, rendered
  short ("fable-5", "sonnet-5", "haiku-4.5") by stripping the "claude-"
  prefix and trailing date suffix; ordered by first appearance.

## Performance

Transcripts run to MBs; the panel must not re-parse them per tick.

- Per-file memoization keyed on (path, mtime, size) — the same
  `FileMemoCache` pattern the subagent scan uses. Cached value per
  file: the list of (timestamp, tokens, model) triples for assistant
  entries in the last 6 hours.
- Only files with mtime within 6 hours are read at all; the scan
  recomputes on watcher reload and on a 60-second timer while the
  panel is open (the countdown displays minutes, so a 1s tick is
  waste).
- Parsing reuses the existing line-tolerant JSONL approach (skip
  undecodable lines).

## UI

- Header row (`PanelContent.sessionList`): existing summary text on the
  left, new `Text("↻ 2h 10m")` right-aligned, 11pt, tertiary — quiet by
  design; it must not compete with the lamp-colored summary.
- Countdown formats as "Nh Mm" above an hour, "Nm" under it, "<1m" at
  the boundary. Hidden entirely (with no placeholder) when no active
  window.
- Tooltip + VoiceOver on the countdown: "2.4M tokens since 12:00 across
  3 sessions · resets at 17:00 · models: fable-5, sonnet-5". Token
  count formats as "2.4M" / "890k" / "12k".
- The reserved stats slot above the footer stays reserved — this
  feature deliberately doesn't use it.

## Edge cases

- No transcripts / no entries in 6h → no countdown, no tooltip.
- Clock skew or out-of-order timestamps → entries sorted before gap
  detection; negative gaps treated as zero.
- A window that started >5h ago with continuous activity: blocks chain
  — the anchor advances to the first entry after each 5h boundary, per
  the rolling-block model.
- Corrupt transcript lines → skipped (existing behavior).
- Session running under an old hook: irrelevant — this feature reads
  transcripts, not session files.

## Testing

Pure Core functions, fixture-driven:

- Block anchoring: single burst, gap-split bursts, ≥5h idle → nil,
  chained blocks across a >5h continuous run.
- Token summing: usage component selection (cache reads excluded),
  malformed usage objects skipped.
- Model shortening: "claude-fable-5" → "fable-5",
  "claude-haiku-4-5-20251001" → "haiku-4.5" style cases, unknown ids
  pass through.
- Countdown/tooltip formatting: hour/minute/boundary cases, token
  magnitude formatting.
- Memoization: cache hit on unchanged (mtime, size), recompute on
  append.
