# Branch labels on session cards (#82)

## Goal

Session cards title as `project — branch` when the session's cwd is a git
repo on a branch: "claude-light — feat/gauge-jitter" instead of just
"claude-light". No branch shown for non-repos, detached HEAD, or sessions
written by older hooks.

## Approach

Hook-side `.git/HEAD` read (issue sketch). The hook shim already runs per
event with the session's cwd; reading one file is cheap and keeps the
"hook writes, app renders" split. Rejected: app-side reads on reload
(polls arbitrary cwds from the watcher loop) and `git branch
--show-current` (fork/exec per hook event — hook perf matters, #43).

## Data flow

1. **Discovery.** From the payload's cwd, walk parent directories to the
   nearest `.git` entry (stop at `/`). Directory → repo root. File → worktree/submodule:
   parse the `gitdir: <path>` line and resolve it (relative paths resolve
   against the file's directory) to find the real git dir.
2. **Parse.** Read `HEAD` in that git dir. `ref: refs/heads/<branch>` →
   branch name (everything after `refs/heads/`, slashes preserved).
   Bare SHA (detached), unreadable, or malformed → nil.
3. **Persist.** `branch` key in the session JSON, next to
   `context_fraction`. Merge semantics: when the payload carries a cwd,
   the fresh read wins — including nil, so switching to detached HEAD
   clears the label. When the payload has no cwd (nothing to discover
   from), the stored value survives, like `context_fraction` across
   transcript-less events. Old apps ignore the key; old hooks never
   write it (no label).
4. **Render.** The title is unchanged (`displayName(for:)` never mentions
   the branch — live testing showed `project — branch` ran too long for
   the card). Instead `cardSubtitle(for:errorReason:)` substitutes the
   branch for the bare status word, with precedence error reason > detail
   (#80) > branch (running/idle only) > friendly status label; a
   needs-you session's detail/question always wins over the branch, since
   a blocked card must say why. `subtitleShowsBranch(for:)` reports
   whether the subtitle currently on screen is the branch, so the view
   layer can style it as a ref — pale amber (sRGB 1.00, 0.76, 0.40),
   11pt regular — rather than prose (12pt `.secondary`). The
   title keeps its single-line tail truncation; no extra branch-length
   cap (YAGNI until it hurts).

## Edge cases

- Detached HEAD / rebase in progress: HEAD holds a SHA → no label.
- Worktrees: `.git` file with absolute or relative `gitdir:` → followed.
- Branch names with slashes/unicode: passed through verbatim.
- cwd deleted mid-session or `.git/HEAD` unreadable: nil, no label.
- Empty cwd (headless): no discovery attempt.

## Testing

Pure-function TDD in ClaudeLightCore:

- HEAD parsing: normal ref, nested branch name, detached SHA, malformed,
  trailing newline variants.
- Discovery: cwd at repo root, nested subdirectory, non-repo, worktree
  file (absolute + relative gitdir), unreadable HEAD. Fixtures build tmp
  directory trees.
- Persistence: fresh read wins when cwd present (nil clears a stale
  branch); stored value survives cwd-less payloads; old-session JSON
  without the key decodes.
- Display: `displayName` with/without branch, headless suffix ordering,
  VoiceOver label composition.
