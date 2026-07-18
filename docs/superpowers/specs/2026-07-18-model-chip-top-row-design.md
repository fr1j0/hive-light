# Model chip: one home in the title row

**Date:** 2026-07-18
**Status:** Approved

## Problem

The model chip renders inside the card's subtitle `HStack`, which only
exists when there is a subtitle to show. In grouped-by-project mode a
running session whose subtitle would just repeat the branch suppresses
that row entirely — so the common card (grouped, running, no pending
question/error) shows no chip at all, regardless of model. Chip
visibility correlates with session *state*, which read as "only works
for Fable" since only subtitle-bearing (Fable) sessions ever showed one.

## Behavior

- The chip moves to the title row's trailing sub-stack, rendered before
  the context ticks: `[title … chip ticks timer]`. One fixed home,
  always visible when `session.model` is known, in every mode and state.
- Visual treatment unchanged: 9pt semibold, 0.5 kerning, tertiary,
  5/1pt padding, 4pt-radius `Color.primary.opacity(0.09)` pill,
  `.help(model)` tooltip, `.layoutPriority(1)` so the title truncates
  before the chip compresses.
- The subtitle row loses the chip and its `Spacer(minLength: 6)`; the
  subtitle text keeps its full width.
- No detection changes — `lastModelID`/`shortModelName` are untouched.

## Code changes

- `Sources/HiveLightApp/SessionCard.swift`: move the chip block from the
  subtitle `HStack` into the gauge/timer `HStack` (before `ContextTicks`);
  update the two comments that describe chip placement.
- No core-logic or test-behavior changes; suite must stay green.

## Out of scope

- Subagent mini-rows still carry no model info (by design).
- Chip content/format unchanged.
