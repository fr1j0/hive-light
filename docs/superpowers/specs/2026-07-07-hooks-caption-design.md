# Hooks Card Caption — Design

**Date:** 2026-07-07
**Status:** Approved (conversation: user clicked "Remove Claude Code hooks",
saw no visible effect, asked what the setting is for)

## Problem

Clicking Install/Remove Claude Code hooks gives no acknowledgment beyond the
button title flipping, and the effect is inherently invisible for a while:
Claude Code snapshots hook configuration at session startup, so
already-running sessions keep (or keep lacking) their hooks until they end,
and recorded session state stays on screen until it expires. The user
reasonably concluded the button did nothing.

## Change

One caption under the hooks button label, inside the clickable card (the
whole card is the tap target — the caption enlarges it, which is fine),
using the settings caption typography (10 pt, `.tertiary`):

> Changes apply to new Claude Code sessions — ones already running keep
> their current hooks until they end.

The text is direction-neutral: it is true for both install and remove, so it
is static — no state-dependent wording.

## Out of scope

- No change to install/uninstall behavior, `hooksInstalled` detection, or
  the `hookActionError` surface.
- No captions elsewhere; the other cards already have theirs.

## Testing

View-only; suite runs as regression gate. Live check: caption renders under
both button titles without clipping, and the card's hover fill covers the
grown card.
