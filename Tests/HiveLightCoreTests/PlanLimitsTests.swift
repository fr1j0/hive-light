import XCTest
@testable import HiveLightCore

final class PlanLimitsTests: XCTestCase {
    /// Real response shape, captured live 2026-07-06.
    private let realShape = """
    {"five_hour":{"utilization":9.0},"limits":[
      {"kind":"session","group":"session","percent":9,"severity":"normal","resets_at":"2026-07-06T05:00:00.330921+00:00","scope":null,"is_active":false},
      {"kind":"weekly_all","group":"weekly","percent":33,"severity":"normal","resets_at":"2026-07-07T19:00:00.330945+00:00","scope":null,"is_active":false},
      {"kind":"weekly_scoped","group":"weekly","percent":53,"severity":"normal","resets_at":"2026-07-07T19:00:00.331249+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}
    ]}
    """.data(using: .utf8)!

    func test_decodesRealShape_withLabelsAndDates() {
        let limits = planLimits(fromJSON: realShape)
        XCTAssertEqual(limits.count, 3)
        XCTAssertEqual(limits[0].kind, "session")
        XCTAssertEqual(limits[0].label, "Session")
        XCTAssertEqual(limits[0].percent, 9)
        XCTAssertNotNil(limits[0].resetsAt)   // 6-digit fractional offset form must parse
        XCTAssertEqual(limits[1].label, "Week · all")
        XCTAssertEqual(limits[2].label, "Week · Fable")   // scope display name
        XCTAssertEqual(limits[2].percent, 53)
    }

    func test_unknownKind_keptWithKindAsLabel() {
        let json = Data(#"{"limits":[{"kind":"monthly_beta","percent":10,"severity":"normal"}]}"#.utf8)
        let limits = planLimits(fromJSON: json)
        XCTAssertEqual(limits.first?.label, "monthly_beta")
        XCTAssertNil(limits.first?.resetsAt)   // missing resets_at tolerated
    }

    func test_garbledOrMissingLimits_returnsEmpty() {
        XCTAssertTrue(planLimits(fromJSON: Data(#"{"limits":"nope"}"#.utf8)).isEmpty)
        XCTAssertTrue(planLimits(fromJSON: Data(#"{"five_hour":{}}"#.utf8)).isEmpty)
        XCTAssertTrue(planLimits(fromJSON: Data("not json".utf8)).isEmpty)
    }

    func test_limitLevel_thresholdsAndSeverityOverride() {
        func limit(_ pct: Int, severity: String = "normal") -> PlanLimit {
            PlanLimit(kind: "session", label: "Session", percent: pct, severity: severity, resetsAt: nil)
        }
        XCTAssertEqual(limitLevel(limit(9)), .ok)
        XCTAssertEqual(limitLevel(limit(75)), .warm)
        XCTAssertEqual(limitLevel(limit(90)), .hot)
        XCTAssertEqual(limitLevel(limit(10, severity: "warning")), .warm)   // server flag wins
        XCTAssertEqual(limitLevel(limit(10, severity: "exceeded")), .hot)
    }

    func test_limitResetText_compactCountdown() {
        let now = ISO8601DateFormatter().date(from: "2026-07-06T02:24:00Z")!
        let sessionReset = ISO8601DateFormatter().date(from: "2026-07-06T05:00:00Z")!
        XCTAssertEqual(limitResetText(kind: "session", resetsAt: sessionReset, now: now), "2h 36m")
        XCTAssertNil(limitResetText(kind: "session", resetsAt: nil, now: now))
        // Beyond a day, every kind compresses to days+hours ("3d 10h").
        let weekly = ISO8601DateFormatter().date(from: "2026-07-09T12:24:00Z")!
        XCTAssertEqual(limitResetText(kind: "weekly_all", resetsAt: weekly, now: now), "3d 10h")
        // Under a day, weekly kinds count down like the session does.
        XCTAssertEqual(limitResetText(kind: "weekly_all", resetsAt: sessionReset, now: now), "2h 36m")
    }
}
