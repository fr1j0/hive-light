# Hive-Themed App Icon — Design

**Date:** 2026-07-07
**Status:** Approved (approach confirmed after clarifying that the artwork itself is never modified)

## What

Adopt the user-supplied hive-themed artwork — the three-lamp traffic-light
pill on a dark honeycomb plate with amber seam glow — as the Hive Light app
icon, replacing the previous rendered icon everywhere the icon pipeline
already reaches: Dock/app icon (`Resources/AppIcon.icns`), notification
banners (catalog derived at packaging), and the README hero
(`assets/app-icon.png`).

## Constraint: the artwork is untouched

Every pixel inside the plate stays exactly as supplied — no recoloring, no
cropping of the design, no compositing. The ONLY transformation is
alpha-masking the region OUTSIDE the plate's rounded-rect silhouette: the
source PNG (1024×1024, no alpha channel) fills its corners with solid black
(verified pure 0,0,0), and macOS expects transparency there so the Dock
tile shows the plate's own rounded shape instead of a black square.

## Source

- Supplied file: 1024×1024 PNG, no alpha, plate edge begins ~30 px from the
  file edge (measured); background pure black everywhere outside the plate.
- Working copy of the source is staged into the repo as the new
  `assets/app-icon.png` after masking.

## Transformation (one-off script, not committed as pipeline)

A scratch Swift script (AppKit, same toolchain as `make-icns.sh`):

1. Measure the plate bounds: scan rows/columns for the first non-black
   pixel (threshold: any channel > 8/255) to get the plate rect.
2. Estimate the corner radius by walking the plate's corner arc (first
   non-black pixel per row within the corner region).
3. Draw the source image through a rounded-rect clip of those measured
   bounds/radius into a fresh RGBA canvas — anti-aliased edge, everything
   outside fully transparent.
4. Write to `assets/app-icon.png`.

Acceptance for the mask: corners fully transparent (alpha 0), plate
interior byte-identical to the source (spot-check sample pixels), edge
anti-aliasing ≤ ~2 px band.

## Pipeline (existing, unchanged)

- `scripts/make-icns.sh` regenerates `Resources/AppIcon.icns` from the new
  `assets/app-icon.png` (scales to Apple's 824 px grid box on a transparent
  1024 canvas — the standard margin every Dock icon gets).
- `scripts/package-app.sh` already derives the notification-banner asset
  catalog from the `.icns` (#59) — no changes.
- README hero is the same `assets/app-icon.png` — updates by itself.

## Cleanup

- Delete `assets/app-icon.svg`: it was the vector source of the OLD icon
  and would silently regenerate the old look. The new source of truth is
  the raster artwork.
- `assets/traffic-light.{png,svg}` stay — they are separate menu-bar
  illustration assets, not the app icon.

## Out of scope

- Menu-bar icon (`TrafficLightIcon.swift` template drawing) — unchanged.
- Release/version bump — the icon rides the next release together with the
  footer cell bullet.
- No bundle-ID or signing changes; notification permissions unaffected.

## Verification

Live check per the established flow: `make-icns.sh`, `package-app.sh`,
re-sign, swap into /Applications, relaunch. Confirm: Dock tile shows the
plate silhouette (no black square), Finder/Get Info icon correct, a test
notification banner carries the new icon, README hero renders as a floating
plate on both GitHub themes. User's visual verdict is the gate; a discard
(revert + rebuild from the old committed assets) is a valid outcome.
