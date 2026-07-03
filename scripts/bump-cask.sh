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
