# Normalize Panel Spacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the main session-list view breathe at the same 12pt-frame / 10pt-gap rhythm as the Settings pane, so the header and footer no longer read as tighter than Settings.

**Architecture:** Pure SwiftUI spacing edit in `PanelContent.sessionList` — bump outer padding and stack spacing to match `SettingsPane`, and remove two ad-hoc paddings that break the rhythm.

**Tech Stack:** SwiftUI (macOS MenuBarExtra `.window` panel), Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-07-05-normalize-panel-spacing-design.md`

## Global Constraints

- Only `Sources/ClaudeLightApp/PanelContent.swift` may change. No `ClaudeLightCore` changes, no `SettingsPane.swift` changes.
- The existing full test suite (279 tests) must pass unmodified — `swift test`.
- Panel width stays `340` (`.frame(width: 340)` in `body`) — do not touch.
- `scrolledListHeight = 480` stays exactly as-is.
- Target rhythm (from `SettingsPane`, unchanged): `VStack(spacing: 10)` … `.padding(12)`.
- No view-snapshot harness exists; the gate is `swift build` + full-suite regression + human visual check.

---

### Task 1: Adopt the Settings rhythm in the session-list view

**Files:**
- Modify: `Sources/ClaudeLightApp/PanelContent.swift` — `sessionList(now:)` (~lines 44-70) and `footer` (~lines 92-123)

**Interfaces:**
- Consumes: nothing new. Pure spacing edit.
- Produces: nothing for later tasks — this is the only task.

- [ ] **Step 1: Bump the outer stack spacing and frame padding**

In `sessionList(now:)`, change the outer `VStack` spacing from `4` to `10`:

```swift
        VStack(alignment: .leading, spacing: 10) {
```

and change the closing `.padding(8)` to `.padding(12)`:

```swift
        }
        .padding(12)
    }
```

- [ ] **Step 2: Drop the ad-hoc header top padding**

In the header `HStack` inside `sessionList(now:)`, remove the `.padding(.top, 4)` line, keeping the horizontal padding:

Before:
```swift
                .padding(.horizontal, 10)
                .padding(.top, 4)
                Divider()
```

After:
```swift
                .padding(.horizontal, 10)
                Divider()
```

- [ ] **Step 3: Drop the ad-hoc footer bottom padding**

In the `footer` property, remove the `.padding(.bottom, 2)` line, keeping the horizontal padding:

Before:
```swift
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }
```

After:
```swift
        }
        .padding(.horizontal, 10)
    }
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build 2>&1 | tail -1 && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1`
Expected: `Build complete!` and `Executed 279 tests, with 0 failures`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightApp/PanelContent.swift
git commit -m "feat: normalize panel spacing to the Settings rhythm"
```

---

### Manual verification (after the task, human-driven)

Build and run the menu bar app locally, then check:

1. **Rhythm match** — flip between the session list and the Settings pane (gear → Back). Header, footer, and both views share one visual rhythm; no view reads as tighter or airier than the others.
2. **Populated list** — with sessions present, the header and footer breathe evenly around the cards.
3. **Empty state** — with zero sessions ("No active Claude Code sessions" text), the panel still looks balanced, not top- or bottom-heavy.
