import XCTest
@testable import ClaudeLightCore

final class SessionTests: XCTestCase {
    func test_session_roundTrips_throughJSON_withSnakeCaseKeys() throws {
        let date = Date(timeIntervalSince1970: 1_719_745_200) // fixed
        let session = Session(
            sessionID: "abc123",
            status: .running,
            project: "vatios",
            cwd: "/Users/x/vatios",
            updatedAt: date
        )

        let data = try ClaudeLightJSON.encoder.encode(session)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"session_id\":\"abc123\""))
        XCTAssertTrue(json.contains("\"status\":\"running\""))
        XCTAssertTrue(json.contains("\"updated_at\""))

        let decoded = try ClaudeLightJSON.decoder.decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
    }

    func test_transcriptPath_roundTrips_andDefaultsNilOnOldJSON() throws {
        let s = Session(sessionID: "x", status: .running, project: "p", cwd: "/p",
                        updatedAt: Date(timeIntervalSince1970: 1000), transcriptPath: "/t.jsonl")
        let data = try ClaudeLightJSON.encoder.encode(s)
        XCTAssertEqual(try ClaudeLightJSON.decoder.decode(Session.self, from: data).transcriptPath, "/t.jsonl")

        let old = #"{"session_id":"y","status":"idle","project":"p","cwd":"/p","updated_at":"1970-01-01T00:16:40Z"}"#
        let decoded = try ClaudeLightJSON.decoder.decode(Session.self, from: Data(old.utf8))
        XCTAssertNil(decoded.transcriptPath)
    }

    func test_handoffStatus_roundTrips_throughJSON() throws {
        let s = Session(sessionID: "h1", status: .handoff, project: "p", cwd: "/p",
                        updatedAt: Date(timeIntervalSince1970: 1000))
        let data = try ClaudeLightJSON.encoder.encode(s)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"status\":\"handoff\""))
        XCTAssertEqual(try ClaudeLightJSON.decoder.decode(Session.self, from: data), s)
    }

    func test_branch_roundTrips() throws {
        let s = Session(sessionID: "b1", status: .running, project: "p", cwd: "/x",
                        updatedAt: Date(timeIntervalSince1970: 1_719_745_200),
                        branch: "feat/labels")
        let data = try ClaudeLightJSON.encoder.encode(s)
        let back = try ClaudeLightJSON.decoder.decode(Session.self, from: data)
        XCTAssertEqual(back.branch, "feat/labels")
    }

    func test_sessionJSON_withoutBranchKey_decodes() throws {
        let json = #"{"session_id":"b2","status":"idle","project":"p","cwd":"/x","updated_at":"2026-07-05T08:00:00Z"}"#
        let s = try ClaudeLightJSON.decoder.decode(Session.self, from: Data(json.utf8))
        XCTAssertNil(s.branch)
    }
}
