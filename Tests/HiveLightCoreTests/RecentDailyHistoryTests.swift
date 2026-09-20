import XCTest
@testable import HiveLightCore

final class RecentDailyHistoryTests: XCTestCase {
    private func day(_ date: String) -> DailyModelTokens {
        DailyModelTokens(date: date, tokensByModel: ["claude-fable-5-1": 100])
    }

    func testKeepsOnlyDaysInsideTheWindowBeforeToday() {
        let history = ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19"].map(day)
        let rows = recentDailyHistory(history, todayKey: "2026-09-20", days: 4)
        XCTAssertEqual(rows.map(\.date), ["2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19"])
    }

    /// The bug: a cache last computed weeks ago must not pose as recent days.
    func testStaleCacheYieldsNoRows() {
        let history = ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-06"].map(day)
        XCTAssertTrue(recentDailyHistory(history, todayKey: "2026-09-20", days: 4).isEmpty)
    }

    func testPartlyStaleCacheKeepsOnlyTheFreshDays() {
        let history = ["2026-08-06", "2026-09-18", "2026-09-19"].map(day)
        let rows = recentDailyHistory(history, todayKey: "2026-09-20", days: 4)
        XCTAssertEqual(rows.map(\.date), ["2026-09-18", "2026-09-19"])
    }

    /// The live scanner owns today's row; a cache entry for today is dropped.
    func testExcludesTodayAndFutureDates() {
        let history = ["2026-09-19", "2026-09-20", "2026-09-21"].map(day)
        let rows = recentDailyHistory(history, todayKey: "2026-09-20", days: 4)
        XCTAssertEqual(rows.map(\.date), ["2026-09-19"])
    }

    func testSortsChronologicallyAndCrossesMonthBoundary() {
        let history = ["2026-10-01", "2026-09-29", "2026-09-30"].map(day)
        let rows = recentDailyHistory(history, todayKey: "2026-10-02", days: 4)
        XCTAssertEqual(rows.map(\.date), ["2026-09-29", "2026-09-30", "2026-10-01"])
    }

    func testMalformedTodayKeyYieldsNoRows() {
        XCTAssertTrue(recentDailyHistory([day("2026-09-19")], todayKey: "garbage", days: 4).isEmpty)
    }
}
