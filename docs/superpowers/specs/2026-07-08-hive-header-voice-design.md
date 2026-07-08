# Hive Header Voice — Design

**Date:** 2026-07-08
**Status:** Approved (mockups + voice set chosen live)

## Goal

Give the dropdown's summary header a hive-voiced title while keeping the facts.
Whimsy lives in the title; the factual counts live in the subtitle; the dot
keeps standard lamp geometry and gains the same halo the menu-bar icon ships.

## Voice — set "Keeper" (fixed phrase per state, never rotated)

| Aggregate state | Title | Subtitle |
|---|---|---|
| needs you (error/waiting/attention/handoff) | The hive needs its keeper | existing counts text ("1 error · 2 need you · 3 working") |
| working (running, nothing needing you) | Hive is humming | "3 working" (+ " · 2 idle" when present) |
| idle only | Hive is calm | "4 sessions idle" ("1 session idle") |
| no sessions | Hive is asleep | "No live sessions" |

## Model

`HeaderVoice { title, subtitle }` + pure `headerVoice(for: StatusCounts)` in
HiveLightCore (unit-tested). Precedence mirrors the icon: needs-you > working
> idle > empty. `summaryText` stays for the needs-you subtitle.

## Presentation (PanelContent)

- Header always renders — including the empty state, which replaces the
  "No active Claude Code sessions" placeholder row (the asleep header carries
  that information now).
- Dot: 11pt lamp in the aggregate state color with a soft same-color halo
  (`.shadow(color: dot.opacity(0.55), radius: 4)`), matching the menu-bar
  icon's glow. Empty state: hollow ring (strokeBorder, secondary), no halo.
- Title: 13pt semibold, primary color — never a status or amber color.
- Subtitle: 11pt secondary — the line the old single-line summary becomes.

## Non-goals

Halos on per-session row dots (noise in long lists); phrase rotation or
randomization; localization.
