import XCTest
@testable import HiveLightCore

final class PlatformStatusTests: XCTestCase {
    /// Real response shape, captured live 2026-09-20 (trimmed to the fields
    /// that matter plus an unwatched product).
    private func payload(api: String = "operational", code: String = "operational") -> Data {
        Data("""
        {"page":{"id":"tymt9n04zgry","name":"Claude","url":"https://status.claude.com"},
         "components":[
          {"id":"rwppv331jlwc","name":"claude.ai","status":"major_outage","group":false},
          {"id":"k8w3r06qmzrp","name":"Claude API (api.anthropic.com)","status":"\(api)","group":false,"position":3},
          {"id":"yyzkbfz2thpt","name":"Claude Code","status":"\(code)","group":false,"position":4}
         ]}
        """.utf8)
    }

    func testOperationalShape_keepsOnlyWatchedProducts_codeFirst() {
        let rows = platformStatus(fromJSON: payload())
        XCTAssertEqual(rows.map(\.label), ["Claude Code", "Claude API"])
        XCTAssertEqual(rows.map(\.state), [.operational, .operational])
    }

    func testDecodesEveryStatuspageState() {
        let cases: [(String, PlatformState)] = [
            ("operational", .operational),
            ("degraded_performance", .degraded),
            ("partial_outage", .partialOutage),
            ("major_outage", .majorOutage),
            ("under_maintenance", .maintenance),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(platformStatus(fromJSON: payload(api: raw)).last?.state, expected, raw)
        }
    }

    /// A state Statuspage adds later must still surface, not vanish.
    func testUnknownStateIsKeptVerbatim() {
        let rows = platformStatus(fromJSON: payload(code: "on_fire"))
        XCTAssertEqual(rows.first?.state, .other("on_fire"))
        XCTAssertEqual(rows.first?.state.text, "on fire")
    }

    func testStateText() {
        XCTAssertEqual(PlatformState.operational.text, "operational")
        XCTAssertEqual(PlatformState.degraded.text, "degraded performance")
        XCTAssertEqual(PlatformState.partialOutage.text, "partial outage")
        XCTAssertEqual(PlatformState.majorOutage.text, "major outage")
        XCTAssertEqual(PlatformState.maintenance.text, "under maintenance")
    }

    func testOnlyOperationalIsHealthy() {
        XCTAssertTrue(PlatformState.operational.isHealthy)
        for s: PlatformState in [.degraded, .partialOutage, .majorOutage, .maintenance, .other("x")] {
            XCTAssertFalse(s.isHealthy)
        }
    }

    /// The API component could be renamed; a product still matches by id.
    func testMatchesByIdWhenNameChanges() {
        let json = Data(#"{"components":[{"id":"k8w3r06qmzrp","name":"Anthropic API","status":"partial_outage"}]}"#.utf8)
        let rows = platformStatus(fromJSON: json)
        XCTAssertEqual(rows.map(\.label), ["Claude API"])
        XCTAssertEqual(rows.first?.state, .partialOutage)
    }

    func testMissingProductIsSimplyAbsent() {
        let json = Data(#"{"components":[{"id":"yyzkbfz2thpt","name":"Claude Code","status":"operational"}]}"#.utf8)
        XCTAssertEqual(platformStatus(fromJSON: json).map(\.label), ["Claude Code"])
    }

    func testMalformedOrReshapedYieldsNothing() {
        XCTAssertTrue(platformStatus(fromJSON: Data(#"{"components":[{"id":"yyzkbf"#.utf8)).isEmpty)
        XCTAssertTrue(platformStatus(fromJSON: Data(#"{"something":"else"}"#.utf8)).isEmpty)
        XCTAssertTrue(platformStatus(fromJSON: Data()).isEmpty)
    }
}
