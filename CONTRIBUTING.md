# Contributing to Hive Light

Thanks for your interest! Hive Light is a young project with a deliberately tight
scope: a native macOS menu-bar monitor for Claude Code sessions. Contributions are
welcome — here's how to make yours land smoothly.

## Before you code

- **Bug fixes and small improvements:** open a PR directly, or file a
  [bug report](https://github.com/fr1j0/claude-light/issues/new?template=bug_report.yml)
  first if you want a sanity check.
- **New features:** open a
  [feature request](https://github.com/fr1j0/claude-light/issues/new?template=feature_request.yml)
  first and wait for a maintainer thumbs-up. The
  project says no to a lot of reasonable ideas to stay small — for example, routine
  state transitions get passive UI, never notifications. An approved issue saves you
  from building something that won't be merged.

## The flow

1. Fork and branch off `main`: `<type>/<slug>` (e.g. `fix/empty-session-card`,
   `feat/warp-focus`). Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.
   Never push to `main` directly.
2. Make your change. New behavior needs tests — the suite is fast, pure-logic tests
   live in `Tests/`, and test-first is how most of this codebase was written.
3. Verify locally before pushing:

   ```bash
   swift build
   swift test
   ```

4. Open a PR against `main` with a short description of what changed and why.
   CI must pass before merge.

## What makes a PR easy to merge

- One concern per PR — a fix and a refactor are two PRs.
- Tests that fail without your change and pass with it.
- UI changes include a screenshot (light and dark menu bar if the icon is affected).
- Match the style around you; no new dependencies without prior discussion —
  Hive Light is pure Swift/SwiftUI with zero third-party dependencies, and
  keeping it that way is a feature.

## Project layout

- `Sources/HiveLightCore/` — pure logic (state, parsing, formatting). Most changes
  belong here, with tests.
- `Sources/HiveLightApp/` — the SwiftUI app shell, menu-bar UI, macOS integration.
- `Sources/hive-light-hook/` — the hook shim binary Claude Code invokes.
- `scripts/` — packaging and release tooling.
- `Casks/` — the Homebrew cask (mirrored to the tap on release).
- `docs/superpowers/specs/` — design specs for shipped features.

## Code of Conduct

Be kind. Assume good faith. If something feels off, open an issue or reach out to
the maintainer.

## License

By contributing, you agree your work is licensed under [Apache-2.0](LICENSE). The
project name, logo, and icon are trademarks of the maintainer and stay out of the
license — see [TRADEMARK.md](TRADEMARK.md).
