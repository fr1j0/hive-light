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

    func test_decodesScopeModel_nameAndNullId() {
        let limits = planLimits(fromJSON: realShape)
        XCTAssertNil(limits[0].scopeModelName)              // session: no scope
        XCTAssertNil(limits[1].scopeModelName)              // weekly_all: no scope
        XCTAssertEqual(limits[2].scopeModelName, "Fable")   // per-model bucket
        XCTAssertNil(limits[2].scopeModelID)                // server withheld the id
    }

    func test_perModelDefaultVisibility_idNullHidesFableIdPresentShows() {
        // Off-plan leftover (id null) → hidden by default; entitled scoped
        // model (id present) → shown.
        let fable = PlanLimit(kind: "weekly_scoped", label: "Week · Fable", percent: 56,
                              severity: "normal", resetsAt: nil,
                              scopeModelName: "Fable", scopeModelID: nil)
        let entitled = PlanLimit(kind: "weekly_scoped", label: "Week · Opus", percent: 20,
                                 severity: "normal", resetsAt: nil,
                                 scopeModelName: "Opus", scopeModelID: "claude-opus-4-8")
        let session = PlanLimit(kind: "session", label: "Session", percent: 9,
                                severity: "normal", resetsAt: nil)
        XCTAssertTrue(isPerModelLimit(fable))
        XCTAssertFalse(isPerModelLimit(session))
        XCTAssertFalse(perModelLimitDefaultVisible(fable))
        XCTAssertTrue(perModelLimitDefaultVisible(entitled))
    }

    func test_visibleLimits_autoHidesNullIdUnlessOverridden() {
        let limits = planLimits(fromJSON: realShape)   // session, weekly_all, Fable(id null)
        // No overrides: Fable auto-hidden, universal buckets kept.
        let auto = visibleLimits(limits, overrides: [:])
        XCTAssertEqual(auto.map(\.label), ["Session", "Week · all"])
        // User re-shows Fable.
        let shown = visibleLimits(limits, overrides: ["Fable": true])
        XCTAssertEqual(shown.map(\.label), ["Session", "Week · all", "Week · Fable"])
        // User hides an otherwise-visible model → universal buckets still pass.
        let hiddenOverride = visibleLimits(limits, overrides: ["Fable": false])
        XCTAssertEqual(hiddenOverride.count, 2)
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
