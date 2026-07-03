import XCTest
@testable import ClaudeLightCore

final class FocusStrategyTests: XCTestCase {
    func test_terminalApp_withTTY_focusesTabByTTY() {
        XCTAssertEqual(focusStrategy(termProgram: "Apple_Terminal", tty: "ttys008"),
                       .terminalApp(tty: "ttys008"))
    }

    func test_iterm_withTTY_focusesSessionByTTY() {
        XCTAssertEqual(focusStrategy(termProgram: "iTerm.app", tty: "ttys003"),
                       .iterm(tty: "ttys003"))
    }

    func test_terminalApp_withoutTTY_fallsBackToActivate() {
        XCTAssertEqual(focusStrategy(termProgram: "Apple_Terminal", tty: nil),
                       .activateApp(bundleID: "com.apple.Terminal"))
        XCTAssertEqual(focusStrategy(termProgram: "Apple_Terminal", tty: ""),
                       .activateApp(bundleID: "com.apple.Terminal"))
    }

    func test_iterm_withoutTTY_fallsBackToActivate() {
        XCTAssertEqual(focusStrategy(termProgram: "iTerm.app", tty: ""),
                       .activateApp(bundleID: "com.googlecode.iterm2"))
    }

    func test_warp_withoutFocusURL_activatesApp() {
        XCTAssertEqual(focusStrategy(termProgram: "WarpTerminal", tty: "ttys008"),
                       .activateApp(bundleID: "dev.warp.Warp-Stable"))
    }

    // MARK: – Warp deep link (#62)

    func test_warp_withFocusURL_opensDeepLink() {
        XCTAssertEqual(focusStrategy(termProgram: "WarpTerminal", tty: nil,
                                     focusURL: "warp://session/abc123"),
                       .openURL(url: "warp://session/abc123"))
    }

    func test_warp_withNonWarpFocusURL_fallsBackToActivate() {
        XCTAssertEqual(focusStrategy(termProgram: "WarpTerminal", tty: nil,
                                     focusURL: "https://evil.example/x"),
                       .activateApp(bundleID: "dev.warp.Warp-Stable"))
    }

    func test_otherTerminals_ignoreFocusURL() {
        XCTAssertEqual(focusStrategy(termProgram: "iTerm.app", tty: "ttys003",
                                     focusURL: "warp://session/abc123"),
                       .iterm(tty: "ttys003"))
    }

    func test_vscode_activatesApp() {
        XCTAssertEqual(focusStrategy(termProgram: "vscode", tty: "ttys008"),
                       .activateApp(bundleID: "com.microsoft.VSCode"))
    }

    func test_unknownTerminal_isNone() {
        XCTAssertEqual(focusStrategy(termProgram: "Hyper", tty: "ttys008"), .none)
    }

    func test_nilTermProgram_isNone() {
        XCTAssertEqual(focusStrategy(termProgram: nil, tty: "ttys008"), .none)
    }
}
