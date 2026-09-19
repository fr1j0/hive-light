import XCTest
@testable import HiveLightCore

final class OAuthCredentialsTests: XCTestCase {
    func testExtractsAccessToken() {
        let json = Data(#"{"claudeAiOauth":{"accessToken":"tok-123","refreshToken":"r"}}"#.utf8)
        XCTAssertEqual(oauthAccessToken(fromCredentialsJSON: json), "tok-123")
    }

    /// `security -w` terminates its output with a newline.
    func testToleratesTrailingNewline() {
        let json = Data("{\"claudeAiOauth\":{\"accessToken\":\"tok-123\"}}\n".utf8)
        XCTAssertEqual(oauthAccessToken(fromCredentialsJSON: json), "tok-123")
    }

    func testEmptyTokenIsNil() {
        let json = Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)
        XCTAssertNil(oauthAccessToken(fromCredentialsJSON: json))
    }

    func testMissingOAuthBlockIsNil() {
        let json = Data(#"{"somethingElse":{}}"#.utf8)
        XCTAssertNil(oauthAccessToken(fromCredentialsJSON: json))
    }

    func testTruncatedJSONIsNil() {
        let json = Data(#"{"claudeAiOauth":{"accessTok"#.utf8)
        XCTAssertNil(oauthAccessToken(fromCredentialsJSON: json))
    }
}
