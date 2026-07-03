# Automated Homebrew Tap Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tag push produces a GitHub release *and* an updated Homebrew tap automatically — zero manual cask work per release (#26).

**Architecture:** The repo cask `Casks/claude-light.rb` becomes a never-bumped template (placeholder `version`/`sha256`). A new shared script `scripts/render-cask.sh` rewrites those two literals; `release.yml` gains a final step that renders the template with the real version + checksum and direct-pushes it to the tap repo `fr1j0/homebrew-claude-light` `main` using a `TAP_PUSH_TOKEN` secret. `scripts/bump-cask.sh` is reworked into the manual recovery tool for when that step fails.

**Tech Stack:** bash (strict mode), python3 (stdlib `re` only), GitHub Actions on `macos-14`, `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-07-03-tap-mirror-automation-design.md`

## Global Constraints

- Work on branch `feat/tap-mirror-automation` (already created). Never commit to `main`.
- No AI attribution anywhere: no `Co-Authored-By` trailers, no "Generated with" footers in commits or PRs.
- All shell scripts start with `#!/usr/bin/env bash` + `set -euo pipefail`.
- The tap repo is `fr1j0/homebrew-claude-light`; its cask path is `Casks/claude-light.rb`.
- The release workflow already produces `dist/claude-light.zip.sha256` (format: `<sha>  dist/claude-light.zip`) at `.github/workflows/release.yml:96-99` and creates the release at `:115-122`.
- This repo has no shell-script CI; verification is by running the exact commands in each task.

---

### Task 1: `scripts/render-cask.sh` — shared version/sha256 rewriter

**Files:**
- Create: `scripts/render-cask.sh`

**Interfaces:**
- Produces: `render-cask.sh <cask-file> <version> <sha256>` — rewrites the first `version "..."` and `sha256 "..."` string literals of `<cask-file>` in place. Exits 0 on success; exits non-zero with a message on stderr if the file is missing, args are wrong, or either literal isn't matched exactly once. Tasks 2 and 4 call it with `bash scripts/render-cask.sh ...`.

- [ ] **Step 1: Write the script**

Create `scripts/render-cask.sh` with exactly this content (the Python block is lifted verbatim from the current `bump-cask.sh` `bump()`):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Rewrites the `version` and `sha256` string literals of a cask file in place.
# Shared by release.yml (tap mirror step) and scripts/bump-cask.sh (manual
# recovery). Fails unless exactly one of each literal is replaced.
#
#   scripts/render-cask.sh <cask-file> <version> <sha256>

[ $# -eq 3 ] || { echo "usage: $0 <cask-file> <version> <sha256>" >&2; exit 2; }
FILE="$1"; VERSION="$2"; SHA="$3"
[ -f "$FILE" ] || { echo "cask not found: $FILE" >&2; exit 1; }

python3 - "$FILE" "$VERSION" "$SHA" <<'PY'
import re, sys
path, version, sha = sys.argv[1:4]
s = open(path).read()
s, nv = re.subn(r'(\n[ \t]*version[ \t]+)"[^"]*"', r'\g<1>"%s"' % version, s, count=1)
s, ns = re.subn(r'(\n[ \t]*sha256[ \t]+)"[^"]*"', r'\g<1>"%s"' % sha, s, count=1)
if nv != 1 or ns != 1:
    sys.exit("could not rewrite version/sha256 in %s (version hits=%d sha256 hits=%d)" % (path, nv, ns))
open(path, "w").write(s)
PY
```

Then: `chmod +x scripts/render-cask.sh`

- [ ] **Step 2: Verify the success path**

```bash
tmp=$(mktemp -d)
cp Casks/claude-light.rb "$tmp/test.rb"
bash scripts/render-cask.sh "$tmp/test.rb" 9.9.9 deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
grep -n 'version "9.9.9"' "$tmp/test.rb" && grep -c 'deadbeef' "$tmp/test.rb"
```

Expected: the `grep`s print the rewritten `version` line and `1`; exit code 0. The rest of the file must be byte-identical apart from those two lines: `diff Casks/claude-light.rb "$tmp/test.rb"` shows exactly two changed lines.

- [ ] **Step 3: Verify the failure path**

```bash
echo 'cask "x" do' > "$tmp/broken.rb"
bash scripts/render-cask.sh "$tmp/broken.rb" 1.0.0 abc; echo "exit=$?"
bash scripts/render-cask.sh "$tmp/missing.rb" 1.0.0 abc; echo "exit=$?"
bash scripts/render-cask.sh "$tmp/test.rb" 1.0.0; echo "exit=$?"
rm -rf "$tmp"
```

Expected: `could not rewrite version/sha256 ... (version hits=0 sha256 hits=0)` then `exit=1`; `cask not found` then `exit=1`; `usage:` then `exit=2`. `broken.rb` must be left unmodified (the script writes only after both counts pass).

- [ ] **Step 4: Commit**

```bash
git add scripts/render-cask.sh
git commit -m "feat: add render-cask.sh, shared cask version/sha256 rewriter"
```

---

### Task 2: Rework `scripts/bump-cask.sh` into the manual recovery tool

**Files:**
- Modify: `scripts/bump-cask.sh` (full rewrite, content below)

**Interfaces:**
- Consumes: `bash scripts/render-cask.sh <cask-file> <version> <sha256>` (Task 1).
- Produces: `scripts/bump-cask.sh <version> --tap <tap-checkout-dir>` — downloads + sha-verifies the release zip, copies the template cask over the tap checkout's cask, renders it. `--tap` is now required; the source cask is no longer edited (it's a template after Task 3).

- [ ] **Step 1: Rewrite the script**

Replace the entire content of `scripts/bump-cask.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Manual RECOVERY for the automated tap mirror. Normally release.yml's
# "Mirror cask to Homebrew tap" step updates the tap on every release; run
# this only when that step failed (see the workflow run's log).
#
# Downloads the release zip, computes and VERIFIES its sha256 against the
# published checksum, then renders the template cask (Casks/claude-light.rb)
# with the real version + sha256 into a local tap checkout.
#
#   scripts/bump-cask.sh 0.9.1 --tap ~/src/homebrew-claude-light
#
# It only edits files — commit and push in the tap yourself (as owner you
# can push to the tap's main directly).
# Requires: gh (authenticated), shasum, python3. Runs after the release exists.

REPO="fr1j0/claude-light"

usage() { echo "usage: $0 <version> --tap <tap-checkout-dir>" >&2; exit 2; }

VERSION="${1:-}"; [ -n "$VERSION" ] || usage
shift || true
TAP_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tap) TAP_DIR="${2:-}"; [ -n "$TAP_DIR" ] || usage; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$TAP_DIR" ] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_CASK="$ROOT/Casks/claude-light.rb"
TAP_CASK="$TAP_DIR/Casks/claude-light.rb"
[ -f "$SRC_CASK" ] || { echo "template cask not found: $SRC_CASK" >&2; exit 1; }
[ -d "$TAP_DIR/Casks" ] || { echo "not a tap checkout (no Casks/): $TAP_DIR" >&2; exit 1; }

TAG="v$VERSION"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "→ downloading $REPO release $TAG ..."
gh release download "$TAG" --repo "$REPO" --pattern 'claude-light.zip' --dir "$tmp"
gh release download "$TAG" --repo "$REPO" --pattern 'claude-light.zip.sha256' --dir "$tmp"

published="$(awk '{print $1}' "$tmp/claude-light.zip.sha256")"
actual="$(shasum -a 256 "$tmp/claude-light.zip" | awk '{print $1}')"
if [ "$published" != "$actual" ]; then
  echo "✗ sha256 mismatch: published=$published actual=$actual" >&2
  exit 1
fi
echo "✓ sha256 verified: $actual"

cp "$SRC_CASK" "$TAP_CASK"
bash "$ROOT/scripts/render-cask.sh" "$TAP_CASK" "$VERSION" "$actual"
echo "✓ rendered ${TAP_CASK}"

# Optional lint if brew is available (the tap's CI enforces this on PRs).
if command -v brew >/dev/null 2>&1; then
  if brew style "$TAP_CASK" >/dev/null 2>&1; then
    echo "✓ brew style clean"
  else
    echo "⚠ brew style reported issues — run: brew style $TAP_CASK"
  fi
fi

echo
echo "Done — tap cask rendered (nothing committed). Next, in $TAP_DIR:"
echo "  git commit -am \"chore: claude-light $VERSION\" && git push origin main"
```

- [ ] **Step 2: Verify usage errors**

```bash
bash scripts/bump-cask.sh; echo "exit=$?"
bash scripts/bump-cask.sh 0.9.0; echo "exit=$?"
bash scripts/bump-cask.sh 0.9.0 --tap /nonexistent; echo "exit=$?"
```

Expected: `usage: ...` + `exit=2` for the first two (`--tap` is required now); `not a tap checkout (no Casks/): /nonexistent` + `exit=1` for the third.

- [ ] **Step 3: Verify the real path against the v0.9.0 release**

```bash
faketap=$(mktemp -d) && mkdir -p "$faketap/Casks" && touch "$faketap/Casks/claude-light.rb"
bash scripts/bump-cask.sh 0.9.0 --tap "$faketap"
grep -E 'version|sha256' "$faketap/Casks/claude-light.rb"
rm -rf "$faketap"
```

Expected: `✓ sha256 verified: 3db37bbb...`, `✓ rendered ...`, and the grep shows `version "0.9.0"` and `sha256 "3db37bbb3309af3f2567db7ae7f4dde76b1aa6336f59416d5b69e31480748f33"`. (Run this while `Casks/claude-light.rb` still has real values — before Task 3 — so the render source is the current cask; the check is about plumbing, not values.)

- [ ] **Step 4: Commit**

```bash
git add scripts/bump-cask.sh
git commit -m "refactor: repurpose bump-cask.sh as tap-mirror recovery tool"
```

---

### Task 3: Demote `Casks/claude-light.rb` to a template

**Files:**
- Modify: `Casks/claude-light.rb` (header comment + two literals only)

**Interfaces:**
- Produces: the template file that Task 4's workflow step and Task 2's recovery script copy + render. Everything except `version`/`sha256` remains real, installable cask content.

- [ ] **Step 1: Edit the header and placeholders**

Replace the leading comment block (currently lines 1–3) and the two literals so the file starts:

```ruby
# TEMPLATE — do not hand-bump; version/sha256 below are placeholders.
# On every release, release.yml renders this file with the real values
# (scripts/render-cask.sh) and pushes it to the tap repo
# fr1j0/homebrew-claude-light — which is what `brew install` reads.

cask "claude-light" do
  version "0.0.0-dev"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
```

Every other line of the file stays exactly as it is.

- [ ] **Step 2: Verify the template still renders**

```bash
tmp=$(mktemp -d)
cp Casks/claude-light.rb "$tmp/t.rb"
bash scripts/render-cask.sh "$tmp/t.rb" 0.9.0 3db37bbb3309af3f2567db7ae7f4dde76b1aa6336f59416d5b69e31480748f33
grep -E 'version "0.9.0"|sha256 "3db37bbb' "$tmp/t.rb"
rm -rf "$tmp"
```

Expected: both lines print; exit 0.

- [ ] **Step 3: Commit**

```bash
git add Casks/claude-light.rb
git commit -m "chore: make repo cask a release-rendered template"
```

---

### Task 4: `release.yml` — mirror the cask to the tap

**Files:**
- Modify: `.github/workflows/release.yml` (append one step after "Create GitHub Release", currently the last step at lines 115–122)

**Interfaces:**
- Consumes: `dist/claude-light.zip.sha256` (existing "Generate checksum" step), `Casks/claude-light.rb` template (Task 3), `bash scripts/render-cask.sh` (Task 1), repo secret `TAP_PUSH_TOKEN` (Task 5).

- [ ] **Step 1: Append the workflow step**

Add after the "Create GitHub Release" step, at the same indentation as the other steps:

```yaml
      # Mirrors the rendered cask to the tap so `brew upgrade` serves this
      # release immediately. Skips gracefully when the secret is absent
      # (forks, PAT expiry) — the release itself is already published; the
      # manual fallback is: scripts/bump-cask.sh <version> --tap <checkout>.
      - name: Mirror cask to Homebrew tap
        env:
          TAP_PUSH_TOKEN: ${{ secrets.TAP_PUSH_TOKEN }}
        run: |
          if [ -z "$TAP_PUSH_TOKEN" ]; then
            echo "::notice::TAP_PUSH_TOKEN secret not set — skipping tap mirror"
            exit 0
          fi
          VERSION="${GITHUB_REF_NAME#v}"
          SHA="$(awk '{print $1}' dist/claude-light.zip.sha256)"
          TAP_DIR="$RUNNER_TEMP/tap"
          git clone --depth 1 \
            "https://x-access-token:${TAP_PUSH_TOKEN}@github.com/fr1j0/homebrew-claude-light.git" \
            "$TAP_DIR"
          cp Casks/claude-light.rb "$TAP_DIR/Casks/claude-light.rb"
          bash scripts/render-cask.sh "$TAP_DIR/Casks/claude-light.rb" "$VERSION" "$SHA"
          cd "$TAP_DIR"
          if git diff --quiet; then
            echo "tap already up to date for $VERSION"
            exit 0
          fi
          git -c user.name="github-actions[bot]" \
              -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
              commit -am "chore: claude-light $VERSION"
          git push origin main
```

- [ ] **Step 2: Validate workflow syntax**

```bash
ruby -ryaml -e "YAML.load_file('.github/workflows/release.yml'); puts 'yaml ok'"
```

Expected: `yaml ok` (system Ruby ships with YAML; no install needed).

- [ ] **Step 3: Simulate the step body locally against a scratch bare repo**

This exercises every line of the `run:` block except the real clone URL:

```bash
sim=$(mktemp -d)
# fake tap origin: bare repo containing a stale cask
git init -q "$sim/seed" && mkdir -p "$sim/seed/Casks"
cp Casks/claude-light.rb "$sim/seed/Casks/claude-light.rb"
git -C "$sim/seed" add -A && git -C "$sim/seed" -c user.name=t -c user.email=t@t commit -qm seed
git clone -q --bare "$sim/seed" "$sim/origin.git"
# fake checksum file
echo "3db37bbb3309af3f2567db7ae7f4dde76b1aa6336f59416d5b69e31480748f33  dist/claude-light.zip" > "$sim/claude-light.zip.sha256"

# the step body, with URL/paths substituted
VERSION="0.9.0"
SHA="$(awk '{print $1}' "$sim/claude-light.zip.sha256")"
TAP_DIR="$sim/tap"
git clone -q --depth 1 "$sim/origin.git" "$TAP_DIR"
cp Casks/claude-light.rb "$TAP_DIR/Casks/claude-light.rb"
bash scripts/render-cask.sh "$TAP_DIR/Casks/claude-light.rb" "$VERSION" "$SHA"
cd "$TAP_DIR"
git diff --quiet || echo "diff detected (expected)"
git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" commit -qam "chore: claude-light $VERSION"
git push -q origin main
git -C "$sim/origin.git" log --oneline -1
cd - && rm -rf "$sim"
```

Expected: `diff detected (expected)`, then the origin log shows `chore: claude-light 0.9.0`. Re-running the render+diff on a fresh clone after the push takes the `git diff --quiet` early-exit (idempotency).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "feat: mirror cask to Homebrew tap on release (#26)"
```

---

### Task 5: `TAP_PUSH_TOKEN` secret + PR

**Files:** none (repo settings + PR only)

**Interfaces:**
- Consumes: the complete branch (Tasks 1–4).
- Produces: PR closing #26; repo secret the workflow reads.

- [ ] **Step 1: Ask the user to create the fine-grained PAT** (cannot be automated — needs the browser):

> github.com → Settings → Developer settings → Fine-grained tokens → Generate new token. Name `claude-light-tap-mirror`, expiration your call (calendar the renewal), Repository access: *Only select repositories* → `fr1j0/homebrew-claude-light`, Permissions: *Contents → Read and write*. Copy the token.

- [ ] **Step 2: Store it as the repo secret**

```bash
gh secret set TAP_PUSH_TOKEN --repo fr1j0/claude-light
```

(paste the token at the prompt) — verify with `gh secret list --repo fr1j0/claude-light` showing `TAP_PUSH_TOKEN`.

- [ ] **Step 3: Push branch and open the PR**

```bash
git push -u origin feat/tap-mirror-automation
gh pr create --title "feat: automate Homebrew tap mirror on release" --body "## Summary
- \`release.yml\` now renders \`Casks/claude-light.rb\` with the release version + verified sha256 and pushes it to \`fr1j0/homebrew-claude-light\` \`main\` (skips with a notice when \`TAP_PUSH_TOKEN\` is absent).
- The repo cask is demoted to a never-hand-bumped template (placeholder \`0.0.0-dev\` / zero sha) — no more \`chore/cask-X.Y.Z\` PRs in either repo.
- New \`scripts/render-cask.sh\` holds the single copy of the version/sha rewrite; \`scripts/bump-cask.sh\` is repurposed as the manual recovery tool (\`--tap\` now required).

## Testing
- \`render-cask.sh\`: success + failure paths exercised (exactly-one-replacement guard).
- \`bump-cask.sh\`: run against the real v0.9.0 release into a scratch tap checkout; sha verified.
- Workflow step body: simulated end-to-end against a local bare repo (clone → render → diff-gate → commit → push), including the idempotent re-run path.
- Full end-to-end lands with the next release tag.

Closes #26"
```

- [ ] **Step 4: Note the residual risk in the PR** (comment or body already covers): first fully-automated run happens on the next real tag; if the mirror step fails, the release is unaffected and `scripts/bump-cask.sh <version> --tap <checkout>` is the fallback.

---

## Verification at the next release

Not part of this branch, but the definition of done for #26: on the next `v*` tag, confirm the workflow's "Mirror cask to Homebrew tap" step pushed `chore: claude-light X.Y.Z` to the tap and `brew upgrade --cask claude-light` serves it.
