import XCTest
@testable import HiveLightCore

final class APIErrorDetectionTests: XCTestCase {
    private func syntheticError(_ text: String) -> String {
        #"{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    private func assistant(_ text: String) -> String {
        #"{"type":"assistant","message":{"model":"claude-opus-4-8","role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    private func user(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
    }
    private let toolResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#
    private let hookLine = #"{"type":"hook_success"}"#

    func test_trailingConnectionRefused() {
        let t = [assistant("working"), syntheticError("API Error: Unable to connect to API (ConnectionRefused)")].joined(separator: "\n")
        XCTAssertEqual(apiErrorReason(transcriptJSONL: t), "connection refused")
    }
    func test_trailingConnectionClosed() {
        let t = syntheticError("API Error: Connection closed mid-response. The response above may be incomplete.")
        XCTAssertEqual(apiErrorReason(transcriptJSONL: t), "connection closed")
    }
    func test_recovered_userRepliedAfterError() {
        let t = [syntheticError("API Error: Unable to connect to API (ConnectionRefused)"), user("retry please")].joined(separator: "\n")
        XCTAssertNil(apiErrorReason(transcriptJSONL: t))
    }
    func test_toolResultAfterError_isSkipped_stillError() {
        let t = [syntheticError("API Error: Unable to connect to API (ConnectionRefused)"), toolResult, hookLine].joined(separator: "\n")
        XCTAssertEqual(apiErrorReason(transcriptJSONL: t), "connection refused")
    }
    func test_normalTranscript_isNil() {
        let t = [user("hi"), assistant("all done")].joined(separator: "\n")
        XCTAssertNil(apiErrorReason(transcriptJSONL: t))
    }
    func test_garbageAndEmpty_isNilNoCrash() {
        XCTAssertNil(apiErrorReason(transcriptJSONL: ""))
        XCTAssertNil(apiErrorReason(transcriptJSONL: "not json\n{bad"))
    }
}
