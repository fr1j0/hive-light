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
