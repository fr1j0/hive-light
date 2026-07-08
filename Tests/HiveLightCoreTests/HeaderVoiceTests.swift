import XCTest
@testable import HiveLightCore

final class HeaderVoiceTests: XCTestCase {

    func testNeedsYouWinsAndCarriesCountsSubtitle() {
        let voice = headerVoice(for: StatusCounts(needYou: 2, working: 3, idle: 1, error: 0))
        XCTAssertEqual(voice.title, "The hive needs its keeper")
        XCTAssertEqual(voice.subtitle, "2 need you · 3 working")
    }

    func testErrorAloneIsNeedsKeeper() {
        let voice = headerVoice(for: StatusCounts(needYou: 0, working: 0, idle: 2, error: 1))
        XCTAssertEqual(voice.title, "The hive needs its keeper")
        XCTAssertEqual(voice.subtitle, "1 error")
    }

    func testWorkingIsHummingWithIdleTail() {
        let voice = headerVoice(for: StatusCounts(needYou: 0, working: 3, idle: 2, error: 0))
        XCTAssertEqual(voice.title, "Hive is humming")
        XCTAssertEqual(voice.subtitle, "3 working · 2 idle")
    }

    func testWorkingAloneOmitsIdleTail() {
        let voice = headerVoice(for: StatusCounts(needYou: 0, working: 1, idle: 0, error: 0))
        XCTAssertEqual(voice.title, "Hive is humming")
        XCTAssertEqual(voice.subtitle, "1 working")
    }

    func testIdleOnlyIsCalmWithPluralization() {
        XCTAssertEqual(headerVoice(for: StatusCounts(needYou: 0, working: 0, idle: 4, error: 0)),
                       HeaderVoice(title: "Hive is calm", subtitle: "4 sessions idle"))
        XCTAssertEqual(headerVoice(for: StatusCounts(needYou: 0, working: 0, idle: 1, error: 0)),
                       HeaderVoice(title: "Hive is calm", subtitle: "1 session idle"))
    }

    func testEmptyIsAsleep() {
        XCTAssertEqual(headerVoice(for: StatusCounts(needYou: 0, working: 0, idle: 0, error: 0)),
                       HeaderVoice(title: "Hive is asleep", subtitle: "No live sessions"))
    }
}
