# Automated Homebrew tap mirror on release (#26)

## Problem

Every release requires a manual two-repo dance: bump `version` + `sha256` in
this repo's `Casks/claude-light.rb`, then make the identical edit in the tap
repo `fr1j0/homebrew-claude-light` (what `brew install --cask` actually
reads). Three releases in a row (v0.7.0–v0.9.0) needed two PRs each across
two repos, and the files drift when a step is skipped (#25).

`scripts/bump-cask.sh` (phase 1 of #26) automated the *edit* — verified
sha256, in-place rewrite — but committing, PRing, and merging in both repos
remained manual.

## Goal

A tag push produces a release **and** a tap that serves it, with zero manual
cask work per release.

## Design

### Single source of truth: the repo cask becomes a template

`Casks/claude-light.rb` in claude-light stays the only hand-edited cask —
the place where description, caveats, URL structure, and stanzas are
maintained. Its `version`/`sha256` are no longer hand-bumped:

- `version` is set to the placeholder `"0.0.0-dev"` and `sha256` to 64
  zeros, so stale-looking real values can't mislead anyone.
- The header comment is rewritten to say the tap copy is *generated* from
  this file by `release.yml` at release time, with real `version`/`sha256`
  substituted.

This ends `chore/cask-X.Y.Z` PRs in claude-light entirely. Nothing consumes
the repo cask directly (brew installs read the tap), so the placeholder is
safe.

### Shared rewrite logic

The `version`/`sha256` rewrite currently lives inline in `bump-cask.sh`
(a Python heredoc). It moves to `scripts/render-cask.sh`:

    scripts/render-cask.sh <cask-file> <version> <sha256>

— rewrites the two string literals in place, failing loudly unless exactly
one of each is replaced. Both `bump-cask.sh` and the workflow call it, so
there is one copy of the regex.

### New `release.yml` step: mirror to the tap

Runs after the GitHub Release is created (last step of the job):

1. Compute the zip's sha256 — already in `dist/claude-light.zip.sha256`
   from the existing checksum step; nothing is re-downloaded.
2. Render the cask: copy `Casks/claude-light.rb` to a temp path, run
   `render-cask.sh` on it with the tag's version and the checksum.
3. Clone the tap shallowly, authenticated with the `TAP_PUSH_TOKEN` secret:
   `https://x-access-token:${TAP_PUSH_TOKEN}@github.com/fr1j0/homebrew-claude-light.git`
4. Copy the rendered cask over the tap's `Casks/claude-light.rb`.
5. If `git diff` is empty (workflow re-run), log and exit 0 — idempotent.
6. Commit as `chore: claude-light X.Y.Z` and push to `main`.

Direct push works because the tap's branch protection has `enforce_admins`
disabled — the owner's PAT bypasses the code-owner-review requirement. The
cask content is fully derived from an artifact whose checksum the same
workflow produced, so review would verify nothing.

### Auth (one-time manual setup)

A fine-grained PAT owned by fr1j0:

- Repository access: only `fr1j0/homebrew-claude-light`
- Permissions: Contents — read and write
- Stored as repo secret `TAP_PUSH_TOKEN` in `fr1j0/claude-light`

The workflow step is skipped (with a notice) when the secret is absent, so
forks and PAT-expiry don't break releases.

### No NOTARIZE gate

The tap already serves unsigned pre-releases with the quarantine caveat, so
the mirror runs on every release. When notarization lands (#57), only the
template's caveats text changes — already in #57's scope.

### Failure isolation & fallback

The mirror is the final step, after the release exists. If it fails, the
release is unaffected; the workflow failure notification is the signal to
run the fallback by hand:

    scripts/bump-cask.sh X.Y.Z --tap <tap-checkout>

`bump-cask.sh` is kept and repurposed as this recovery tool (it now calls
`render-cask.sh` for the rewrite). Its help text notes the tap normally
updates automatically.

## Alternatives considered

- **Auto-PR on the tap instead of direct push** — keeps the review gate but
  every release still needs a manual merge; auto-merge can't complete
  because the owner cannot code-owner-approve their own PR. Rejected: it
  shrinks the dance instead of ending it.
- **Keep hand-bumping the repo cask, workflow mirrors it** — preserves the
  `chore/cask-*` PR ritual and the two-hand-edited-files drift risk the
  issue complains about. Rejected.

## Testing

- `render-cask.sh` guards itself: `set -euo pipefail` plus the
  exactly-one-replacement check make an unexpected cask shape fail loudly.
  No CI test — the repo's CI is the Swift suite, and the script is
  exercised on every release.
- `bump-cask.sh` continues to be the manually-exercised recovery path.
- End-to-end validation: the next real release — or a throwaway prerelease
  tag (e.g. `v0.9.1-rc1`) deleted afterwards, if a rehearsal is wanted
  before a real one.

## Out of scope

- Notarization flip and caveats revert (#57).
- Tap CI changes. The tap's `test` check only gates PRs; the mirror's
  direct pushes land without it, same as the owner's existing direct
  pushes. The workflow's own sha verification covers the content.
