import XCTest
@testable import HiveLightCore

final class StatsCacheTests: XCTestCase {
    func test_decodesRealShape() {
        let json = """
        {"version":4,"lastComputedDate":"2026-07-05",
         "dailyModelTokens":[
           {"date":"2026-07-04","tokensByModel":{"claude-fable-5":800000,"claude-sonnet-5":700000}},
           {"date":"2026-07-05","tokensByModel":{"claude-fable-5":1700000}}
         ]}
        """.data(using: .utf8)!
        let rows = dailyModelTokens(fromJSON: json)
        XCTAssertEqual(rows, [
            DailyModelTokens(date: "2026-07-04",
                             tokensByModel: ["claude-fable-5": 800_000, "claude-sonnet-5": 700_000]),
            DailyModelTokens(date: "2026-07-05", tokensByModel: ["claude-fable-5": 1_700_000]),
        ])
    }

    func test_malformedRow_isSkipped_notFatal() {
        let json = """
        {"dailyModelTokens":[
           {"date":"2026-07-04"},
           {"date":"2026-07-05","tokensByModel":{"claude-fable-5":100,"weird":"not a number"}}
         ]}
        """.data(using: .utf8)!
        let rows = dailyModelTokens(fromJSON: json)
        XCTAssertEqual(rows, [DailyModelTokens(date: "2026-07-05",
                                               tokensByModel: ["claude-fable-5": 100])])
    }

    func test_truncatedJSON_returnsEmpty() {
        let json = Data(#"{"dailyModelTokens":[{"date":"2026-0"#.utf8)
        XCTAssertTrue(dailyModelTokens(fromJSON: json).isEmpty)
    }

    func test_missingKey_returnsEmpty() {
        let json = Data(#"{"version":4}"#.utf8)
        XCTAssertTrue(dailyModelTokens(fromJSON: json).isEmpty)
    }
}
