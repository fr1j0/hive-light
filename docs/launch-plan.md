# Claude Light — Launch Plan

_Status: gated on Apple notarization. Written 2026-07-06._

## Gate: Apple notarization

The launch waits on Apple enabling notarization for the team.

- **Blocker (Apple-side):** every `notarytool` submission is rejected with statusCode 7000 — "Team is not yet configured for notarization". Does not auto-clear.
- **Support ticket:** Apple case **102930081454**, filed 2026-07-03; escalated by Apple support (Caleb) to their senior team on 2026-07-04. Response expected by email.
- **Everything else is ready:**
  - Developer ID cert `Developer ID Application: Fernando Castillo (7MTZYB93KB)` in local keychain, valid to 2027-02-01.
  - All 6 GitHub secrets set; credentials verified via `notarytool history`.
  - A fresh verified app-specific password exists (2026-07-03).

## Unlock sequence (when Apple resolves the ticket)

1. Retest with a signed hello-world zip: `notarytool submit --wait`.
2. If **Accepted** → verify/update the `APPLE_APP_PASSWORD` repo secret.
3. Set the repo variable `NOTARIZE=true` (repo settings, maintainer-only).
4. Cut a signed re-release: version bump → tag → release workflow → cask bumps.
5. Verify with `spctl -a -vv` that the artifact reports **Notarized Developer ID**.
6. Revert the interim unsigned-build wording:
   - README: unsigned-build install note + "Security & Trust" paragraph.
   - Cask caveats in both the main repo and the homebrew tap.
   - Note: newer Homebrew requires `brew trust fr1j0/claude-light` for third-party taps — keep that documented in install steps.

## Pre-launch prep — loopwayz.com/claude-light (canonical page)

The portfolio page at loopwayz.com/claude-light is the canonical launch link.

- [ ] Record a panel GIF (menu-bar dropdown showing live sessions, context gauge, model chip, branch labels, subagent rows) + screenshots.
- [ ] Update the stale ad-hoc-signing section once notarization ships.
- [ ] Refresh the feature list — much has shipped since the page was written: custom dropdown panel, context-usage gauge, model chip, branch labels, notification detail text, done-state, question detection, Warp tab focus.
- [ ] Add OpenGraph/Twitter-card meta tags so shared links unfurl properly.
- [ ] Add privacy-friendly analytics (e.g. Plausible/GoatCounter class) to measure the launch burst.

## Launch burst (sequenced, in order)

1. **Show HN** — the centerpiece. Submit the GitHub repo URL (HN convention for open-source tools). Post early on a weekday morning US time. First comment: brief personal story — built to keep track of parallel Claude Code sessions from the macOS menu bar; native Swift, no Electron.
2. **Reddit** — after HN settles. Candidate subreddits: r/ClaudeAI, r/macapps, r/commandline. Tailor each post; link the loopwayz page as canonical.
3. **X** — short demo clip (the GIF), link to loopwayz page. Time it with the Reddit wave.
4. **Awesome lists** — PRs adding claude-light to relevant `awesome-*` repos (awesome-claude / awesome-claude-code, awesome-mac, awesome-menubar).
5. **Product Hunt** — last, once assets (GIF, screenshots, tagline) are proven by the earlier rounds. Needs: gallery images, maker comment, first-day availability to answer questions.

## Positioning notes

- One-liner: native macOS menu-bar monitor for Claude Code sessions — live status, context gauge, current model, branch, and subagents at a glance.
- Differentiators: pure Swift/SwiftUI (no Electron), hook-driven (no polling daemon), works with any terminal (iTerm, Terminal, Warp, VS Code), one-click tab focus.
- Install: `brew tap fr1j0/claude-light && brew install --cask claude-light` (plus `brew trust` on newer Homebrew).
