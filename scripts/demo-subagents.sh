#!/usr/bin/env bash
set -euo pipefail

# Seeds a synthetic RUNNING session whose transcript contains parallel subagents
# so the dropdown shows the fan-out rows (feature from #20). For local/visual testing.
#
#   scripts/demo-subagents.sh          # seed the demo session + enable the toggle
#   scripts/demo-subagents.sh --clean  # remove the demo session
#
# After seeding, open Hive Light — under "demo-fanout — running" you should see:
#     ● Review Task 4
#     ● Final whole-branch review
#     ⚠ Implement Task 5
#     ● Extra subagent A
#     ● Extra subagent B
#     +1 more running
# (Docs pass completes successfully, so it is intentionally hidden.)

BUNDLE_ID="com.fr1j0.hive-light"
STORE="$HOME/.hive-light/sessions"
SESSION_ID="demo-fanout"
SESSION_FILE="$STORE/$SESSION_ID.json"
TRANSCRIPT="$STORE/$SESSION_ID.transcript.jsonl"

if [[ "${1:-}" == "--clean" ]]; then
    rm -f "$SESSION_FILE" "$TRANSCRIPT"
    echo "Removed demo session. (Toggle left as-is; disable via the menu if you want.)"
    exit 0
fi

mkdir -p "$STORE"

# A running host with: running subagents, 1 failed, 1 done (hidden), plus extras
# to trip the +N overflow cap (5 shown, rest counted).
cat > "$TRANSCRIPT" <<'JSONL'
{"type":"user","message":{"role":"user","content":"fan out the work"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u1","name":"Task","input":{"description":"Review Task 4"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u2","name":"Task","input":{"description":"Final whole-branch review"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u3","name":"Task","input":{"description":"Implement Task 5"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u3","is_error":true,"content":"boom"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u4","name":"Task","input":{"description":"Docs pass (completes, hidden)"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"u4","is_error":false,"content":"ok"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u5","name":"Task","input":{"description":"Extra subagent A"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u6","name":"Task","input":{"description":"Extra subagent B"}}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"u7","name":"Task","input":{"description":"Extra subagent C"}}]}}
JSONL

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$SESSION_FILE" <<JSON
{"session_id":"$SESSION_ID","status":"running","project":"demo-fanout","cwd":"$HOME","updated_at":"$NOW","transcript_path":"$TRANSCRIPT"}
JSON

# The feature is opt-in — turn the preference on so the rows appear.
defaults write "$BUNDLE_ID" showSubagents -bool true

echo "Seeded demo session -> $SESSION_FILE"
echo "Enabled 'Show subagents'. Open Hive Light and look under 'demo-fanout — running'."
echo "Clean up with: scripts/demo-subagents.sh --clean"
