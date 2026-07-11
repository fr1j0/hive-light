# Hook Transcript Tail Cap (#106) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cap the hook's transcript read at a 64KB tail (matching the app) and unify both sides on one tail-read implementation in HiveLightCore.

**Architecture:** `readTranscript(atPath:)` in `HiveLightCore/TranscriptReading.swift` gains a `maxBytes: Int = 64 * 1024` parameter and adopts the FileHandle seek-to-tail pattern currently private in `SessionWatcher.transcriptTail`. SessionWatcher then deletes its private copy and calls the core function. The hook (`hive-light-hook/main.swift`) needs no code change — it inherits the cap via the default parameter.

**Tech Stack:** Swift (SwiftPM), XCTest. Test with `swift test` from the repo root.

## Global Constraints

- Branch: all work happens on `fix/hook-transcript-tail-cap` (already checked out); never commit to `main`.
- No AI attribution in commit messages (no `Co-Authored-By`, no "Generated with" footers).
- `readTranscript` keeps its contract: `nil` on I/O failure; lossy UTF-8 decode (the #111 fix) must be preserved.
- Full suite must pass: `swift test` (≈580 tests).

---

### Task 1: Cap `readTranscript` at a 64KB tail

**Files:**
- Modify: `Sources/HiveLightCore/TranscriptReading.swift`
- Test: `Tests/HiveLightCoreTests/TranscriptReadingTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `public func readTranscript(atPath path: String, maxBytes: Int = 64 * 1024) -> String?` — Task 2 calls it with an explicit `maxBytes: 4 * 1024 * 1024`.

- [ ] **Step 1: Write the failing tests**

Append inside the `TranscriptReadingTests` class in `Tests/HiveLightCoreTests/TranscriptReadingTests.swift` (it already has the `writeFixture` helper):

```swift
    /// #106: a transcript larger than `maxBytes` reads only the tail. The
    /// byte-count assertion is the proof of truncation; the extractor
    /// assertions prove the tail is still usable.
    func test_fileLargerThanCap_readsOnlyTail() throws {
        var bytes = Data()
        for _ in 0..<200 {
            bytes.append(Data(#"{"type":"assistant","message":{"role":"assistant","model":"claude-3-5-sonnet-20240620","usage":{"input_tokens":1}}}"#.utf8))
            bytes.append(Data("\n".utf8))
        }
        let recent = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","usage":{"input_tokens":47929}}}"#
        bytes.append(Data(recent.utf8))

        let path = try writeFixture(bytes)
        let cap = recent.utf8.count + 40 // starts the read mid-way through an old line
        let jsonl = try XCTUnwrap(readTranscript(atPath: path, maxBytes: cap))
        XCTAssertLessThanOrEqual(jsonl.utf8.count, cap)
        XCTAssertEqual(lastModelID(transcriptJSONL: jsonl), "claude-opus-4-8")
        XCTAssertEqual(contextFraction(transcriptJSONL: jsonl), 47_929.0 / 1_000_000.0)
    }

    /// #106: when the cap slices mid-line, the partial first line still shows
    /// a tempting `"model"` key but is not valid JSON — the per-line scans
    /// must skip it, not misparse it.
    func test_capSlicedFirstLine_isSkippedNotMisparsed() throws {
        let old = #"{"type":"assistant","message":{"role":"assistant","model":"claude-3-5-sonnet-20240620"}}"#
        let recent = #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8"}}"#
        var bytes = Data((old + "\n").utf8)
        bytes.append(Data(recent.utf8))

        let path = try writeFixture(bytes)
        // Keep the recent line whole plus the last 60 bytes of the old line:
        // enough to include its "model":"claude-3-5-sonnet-20240620" text
        // while making the line unparseable.
        let cap = recent.utf8.count + 1 + 60
        let jsonl = try XCTUnwrap(readTranscript(atPath: path, maxBytes: cap))
        XCTAssertEqual(lastModelID(transcriptJSONL: jsonl), "claude-opus-4-8")
    }
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `swift test --filter TranscriptReadingTests`
Expected: compile FAILURE — `extra argument 'maxBytes' in call` (the parameter doesn't exist yet).

- [ ] **Step 3: Implement the capped read**

Replace the whole of `Sources/HiveLightCore/TranscriptReading.swift` with:

```swift
import Foundation

/// Reads the tail (last `maxBytes`; the whole file if smaller) of a Claude
/// Code transcript for the hook's Stop-path scans (#96/#105) and the app's
/// reload scans (#106). Two truncation edges are expected and safe, because
/// every consumer splits per line and defensively skips unparseable lines:
/// - torn tail: Claude Code appends concurrently, and a strict UTF-8 decode
///   would fail wholesale on a torn multibyte sequence, silently freezing
///   the model chip and context gauge (#111) — decode lossily so only the
///   torn partial line degrades to replacement characters
/// - torn head: the byte cap can slice mid-line, leaving a partial first line
/// nil when the file can't be read (or is empty — no lines to scan either way).
public func readTranscript(atPath path: String, maxBytes: Int = 64 * 1024) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    guard let end = try? handle.seekToEnd() else { return nil }
    let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
    try? handle.seek(toOffset: start)
    guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
    return String(decoding: data, as: UTF8.self)
}
```

Note: this is `SessionWatcher.transcriptTail`'s proven body verbatim, plus the lossy decode both already shared. One behavior nuance is deliberate: an empty file now returns `nil` instead of `""` (matching the app side); no consumer distinguishes the two — every extractor returns `nil` on an empty string anyway.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TranscriptReadingTests`
Expected: PASS — all TranscriptReadingTests including the 3 pre-existing ones (torn UTF-8 tail, verbatim small file, missing file).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS (no other test constructs transcripts anywhere near 64KB, so nothing else should be affected — if something fails, stop and investigate rather than adjusting the failing test).

- [ ] **Step 6: Commit**

```bash
git add Sources/HiveLightCore/TranscriptReading.swift Tests/HiveLightCoreTests/TranscriptReadingTests.swift
git commit -m "perf: cap the hook's transcript read at a 64KB tail (#106)"
```

---

### Task 2: SessionWatcher delegates to the core tail read

**Files:**
- Modify: `Sources/HiveLightApp/SessionWatcher.swift` (call sites ~lines 164 and 174; delete the private `transcriptTail` at ~lines 215–226)
- Modify: `Sources/hive-light-hook/main.swift` (comment only, ~lines 14–15)

**Interfaces:**
- Consumes: `readTranscript(atPath:maxBytes:)` from Task 1 (`HiveLightCore` is already imported by SessionWatcher).
- Produces: nothing new — behavior-preserving refactor.

- [ ] **Step 1: Replace the two call sites**

In `Sources/HiveLightApp/SessionWatcher.swift`, the error-detection read:

```swift
            if let tail = transcriptTail(path: path),
               let reason = apiErrorReason(transcriptJSONL: tail) {
```

becomes:

```swift
            if let tail = readTranscript(atPath: path),
               let reason = apiErrorReason(transcriptJSONL: tail) {
```

and the subagent wide read:

```swift
                let list = subagentCache.value(for: path, stamp: stamp) { [weak self] in
                    guard let wide = self?.transcriptTail(path: path, maxBytes: 4 * 1024 * 1024)
                    else { return .empty }
                    return subagents(fromTranscript: wide)
                }
```

becomes (a free function needs no `self`, so the capture list goes too):

```swift
                let list = subagentCache.value(for: path, stamp: stamp) {
                    guard let wide = readTranscript(atPath: path, maxBytes: 4 * 1024 * 1024)
                    else { return .empty }
                    return subagents(fromTranscript: wide)
                }
```

- [ ] **Step 2: Delete the private duplicate**

Remove this entire function from `Sources/HiveLightApp/SessionWatcher.swift`:

```swift
    /// Reads the last `maxBytes` of a transcript file (whole file if smaller).
    /// Fail-safe: returns nil on any error. A partial first line is fine —
    /// `apiErrorReason` scans bottom-up and skips unparseable lines.
    private func transcriptTail(path: String, maxBytes: Int = 64 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
```

- [ ] **Step 3: Touch up the hook's call-site comment**

In `Sources/hive-light-hook/main.swift`, this comment:

```swift
        // Lossy read: Claude Code appends concurrently and a strict UTF-8
        // decode fails wholesale on a torn tail, freezing chip/gauge (#111).
        transcriptJSONL = readTranscript(atPath: path)
```

becomes:

```swift
        // Lossy, 64KB-tail-capped read (#106): Claude Code appends
        // concurrently and a strict UTF-8 decode fails wholesale on a torn
        // tail (#111); the per-line scans skip both torn edges.
        transcriptJSONL = readTranscript(atPath: path)
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: clean build (no remaining references to `transcriptTail` — verify with `grep -rn "transcriptTail" Sources/` returning nothing), all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HiveLightApp/SessionWatcher.swift Sources/hive-light-hook/main.swift
git commit -m "refactor: unify app and hook on the core transcript tail read (#106)"
```
