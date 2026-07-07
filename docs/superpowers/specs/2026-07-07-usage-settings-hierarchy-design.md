# Usage Settings Hierarchy — Design

**Date:** 2026-07-07
**Status:** Approved (approach confirmed in conversation)

## Problem

The Settings Usage card presents "Show usage stats" and "Show plan limits" as
independent siblings, but the panel consults `showPlanLimits` only inside the
`showUsageStats` gate (`usageRowVisible` in `PanelContent.swift`). With stats
off and limits on — a state the UI happily allows — nothing renders anywhere.
The card already knows how to express a dependency (the limits toggle dims
with an explanatory caption when no OAuth login exists); the stats-off case
never got the same treatment.

## Model

One usage feature, two data sources, limits outrank local stats (the v0.18
row design: fetched limits render the plan-limits mirror; local burn is the
fallback). The settings should say exactly that:

- **Master:** "Show usage in panel" (today's `showUsageStats`, relabeled) —
  owns the usage row's existence. Caption unchanged: "Usage row in the
  panel · click it for details".
- **Source sub-setting:** "Fetch plan limits from Anthropic" (today's
  `showPlanLimits`, relabeled) — disabled and dimmed while the master is
  off, using the exact grammar of the existing no-OAuth disabled state
  (`.disabled` + 0.4 opacity + explanatory caption). **Revised after live
  check:** the spec originally said "no new indentation"; the user approved
  a follow-up iteration nesting the sub-setting's row and caption with a
  12 pt leading inset so the parent/child relationship reads in every
  state, not just when dimmed. The switch column stays right-aligned.

Rejected alternative: making limits standalone (row appears when either
toggle is on). "Limits override stats" is exactly why that's awkward — the
master toggle would then sometimes do nothing, moving the dead-switch
problem to the other switch. The master+source model has no dead
combination.

## Caption states for the sub-setting (priority order)

1. **No OAuth login** (wins — the more fundamental blocker, unchanged):
   "Requires a Claude subscription login in Claude Code — API-key and
   Bedrock/Vertex setups have no plan limits."
2. **Master off:** "Plan limits appear in the usage row — turn on Show
   usage in panel first."
3. **Enabled** (unchanged): "Reads your Claude Code login from the Keychain
   to fetch limits from Anthropic. Nothing else is sent."

Disabled/dim condition becomes `!hasOAuthLogin || !watcher.showUsageStats`.
Flipping the master re-enables the sub-toggle live (`watcher` is observed).

## Explicitly unchanged

- Defaults keys and semantics (`showUsageStats`, `showPlanLimits`) — no
  migration; a stored stats-off/limits-on state simply shows the dimmed
  sub-toggle until the master is flipped.
- `usageRowVisible` predicate and all panel/UsageRow/UsageView behavior.
- The `MiniSwitch` accessibility labels update to match the new visible
  labels; nothing else in the control changes.

## Testing

View-only change in `SettingsPane.swift`, outside the XCTest suite's reach
by design — suite runs as a regression gate. Verification is the live
check: build, re-sign, swap, open Settings; confirm the dim/caption in all
three states (master off; master on + limits off; master on + limits on)
and that flipping the master re-enables the sub-toggle without reopening
Settings.
