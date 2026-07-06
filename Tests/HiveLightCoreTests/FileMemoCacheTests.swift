import XCTest
@testable import HiveLightCore

final class FileMemoCacheTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_719_745_200)

    func test_sameStamp_computesOnce() {
        let cache = FileMemoCache<Int>()
        var computeCount = 0
        let stamp = FileStamp(mtime: t0, size: 100)
        let a = cache.value(for: "/t/a.jsonl", stamp: stamp) { computeCount += 1; return 7 }
        let b = cache.value(for: "/t/a.jsonl", stamp: stamp) { computeCount += 1; return 7 }
        XCTAssertEqual(a, 7)
        XCTAssertEqual(b, 7)
        XCTAssertEqual(computeCount, 1, "unchanged file must not be recomputed")
    }

    func test_changedStamp_recomputes() {
        let cache = FileMemoCache<Int>()
        var computeCount = 0
        _ = cache.value(for: "/t/a.jsonl", stamp: FileStamp(mtime: t0, size: 100)) { computeCount += 1; return 1 }
        let grown = cache.value(for: "/t/a.jsonl", stamp: FileStamp(mtime: t0, size: 200)) { computeCount += 1; return 2 }
        XCTAssertEqual(grown, 2)
        let touched = cache.value(for: "/t/a.jsonl", stamp: FileStamp(mtime: t0.addingTimeInterval(1), size: 200)) { computeCount += 1; return 3 }
        XCTAssertEqual(touched, 3)
        XCTAssertEqual(computeCount, 3)
    }

    func test_pathsAreIndependent() {
        let cache = FileMemoCache<Int>()
        let stamp = FileStamp(mtime: t0, size: 100)
        let a = cache.value(for: "/t/a.jsonl", stamp: stamp) { 1 }
        let b = cache.value(for: "/t/b.jsonl", stamp: stamp) { 2 }
        XCTAssertEqual(a, 1)
        XCTAssertEqual(b, 2)
    }

    func test_evict_dropsEntriesNotKept() {
        let cache = FileMemoCache<Int>()
        let stamp = FileStamp(mtime: t0, size: 100)
        _ = cache.value(for: "/t/gone.jsonl", stamp: stamp) { 1 }
        _ = cache.value(for: "/t/kept.jsonl", stamp: stamp) { 2 }
        cache.evict(keeping: ["/t/kept.jsonl"])
        var recomputed = false
        _ = cache.value(for: "/t/gone.jsonl", stamp: stamp) { recomputed = true; return 1 }
        XCTAssertTrue(recomputed, "evicted entry must recompute")
        var keptRecomputed = false
        _ = cache.value(for: "/t/kept.jsonl", stamp: stamp) { keptRecomputed = true; return 2 }
        XCTAssertFalse(keptRecomputed, "kept entry must stay cached")
    }
}
