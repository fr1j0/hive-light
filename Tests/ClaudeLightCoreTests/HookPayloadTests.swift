import XCTest
@testable import ClaudeLightCore

final class HookPayloadTests: XCTestCase {
    func test_decodes_minimalPayload() throws {
        let json = #"{"session_id":"s1","hook_event_name":"Stop","cwd":"/tmp/proj"}"#
        let p = try ClaudeLightJSON.decoder.decode(HookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.sessionID, "s1")
        XCTAssertEqual(p.hookEventName, "Stop")
        XCTAssertEqual(p.cwd, "/tmp/proj")
        XCTAssertNil(p.message)
    }

    func test_decodes_preToolUseWithToolName() throws {
        let json = #"{"session_id":"s3","hook_event_name":"PreToolUse","cwd":"/tmp/proj","tool_name":"Bash"}"#
        let p = try ClaudeLightJSON.decoder.decode(HookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.toolName, "Bash")
    }

    func test_decodes_notificationWithMessage() throws {
        let json = #"{"session_id":"s2","hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#
        let p = try ClaudeLightJSON.decoder.decode(HookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.message, "Claude needs your permission to use Bash")
        XCTAssertNil(p.cwd)
    }
}
