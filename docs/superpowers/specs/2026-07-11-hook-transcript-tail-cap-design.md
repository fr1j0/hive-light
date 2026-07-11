# Hook transcript tail cap (#106)

## Problem

The hook reads the entire transcript on every event that carries one
(`readTranscript(atPath:)` in `HiveLightCore/TranscriptReading.swift` uses
`FileManager.contents`, i.e. a whole-file read). On Stop, four O(n) line-split
extractors then scan that full string. Long sessions pay this linearly growing
cost on every event (#43 hook-perf budget). The app side already solved this:
`SessionWatcher.transcriptTail` reads only the last 64KB.

## Design

### 1. `HiveLightCore/TranscriptReading.swift` — cap the read

`readTranscript(atPath:)` gains a `maxBytes: Int = 64 * 1024` parameter. The
implementation adopts the FileHandle pattern from `SessionWatcher.transcriptTail`:

- open `FileHandle(forReadingAtPath:)`, `seekToEnd`
- seek back to `end > maxBytes ? end - maxBytes : 0`
- `readToEnd`, then the existing **lossy** `String(decoding:, as: UTF8.self)`

Contract unchanged: returns `nil` on any I/O failure. The #111 torn-tail
guarantee is preserved because the decode stays lossy. The new partial
*first* line (when the cap slices mid-line) is safe because every consumer
(`pendingUserQuestionText`, `lastAssistantText`, `contextFraction`,
`lastModelID`, `apiErrorReason`) splits per line and defensively skips
unparseable lines. The doc comment states both truncation edges: torn tail
from concurrent append, torn head from the cap.

### 2. `HiveLightApp/SessionWatcher.swift` — delegate to core

Delete the private `transcriptTail(path:maxBytes:)` and call
`readTranscript(atPath:maxBytes:)` at its two call sites:

- error detection: default 64KB
- subagent wide read: `4 * 1024 * 1024`

One tail-read implementation, living in Core where it's testable.

### 3. Hook (`hive-light-hook/main.swift`) — no code change

The hook picks up the cap through the default parameter. Its call-site
comment gets a one-line touch-up: the read is now lossy *and* tail-capped.

## Testing (TDD, `TranscriptReadingTests`)

New tests written before implementation:

- a file larger than a small explicit `maxBytes` returns only the tail, and
  the extractors still find the last model / context fraction
- the cap slicing mid-line leaves a partial first line that extractors skip
  without misparsing
- existing tests (torn UTF-8 tail, verbatim small file, missing file) keep
  passing unchanged — small files are below the cap

App-side behavior is covered by the same core tests since SessionWatcher now
delegates.

## Out of scope (deferred in #106)

- merging the four extractors' line-splits into one shared split — once the
  input is capped at 64KB, four splits are negligible
- tidying `shortModelName`'s legacy-id rendering
