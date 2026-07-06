import XCTest
@testable import HiveLightCore

final class ShellQuotingTests: XCTestCase {

    // MARK: – Pure quoting correctness

    func test_shellQuoted_pathWithSpace() {
        let path = "/Applications/Hive Light.app/Contents/MacOS/hive-light-hook"
        XCTAssertEqual(
            shellQuoted(path),
            "'/Applications/Hive Light.app/Contents/MacOS/hive-light-hook'"
        )
    }

    func test_shellQuoted_embeddedSingleQuote() {
        XCTAssertEqual(shellQuoted("/a'b"), "'/a'\\''b'")
    }

    // MARK: – Execution round-trip: proves the bug is fixed

    func test_shellQuoted_roundTripExecution() throws {
        // Build a temp dir whose name contains a space.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("shell quoting test \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let scriptURL = base.appendingPathComponent("probe.sh")
        let scriptPath = scriptURL.path

        // Write a tiny probe script.
        try "#!/bin/sh\necho ok\n".write(to: scriptURL, atomically: true, encoding: .utf8)

        // chmod +x
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath
        )

        // --- QUOTED path: must succeed and print "ok" ---
        let quotedOutput = try runShellCommand(shellQuoted(scriptPath))
        XCTAssertEqual(quotedOutput.trimmingCharacters(in: .whitespacesAndNewlines), "ok",
                       "quoted path should execute and print 'ok'")

        // --- UNQUOTED path: must NOT successfully print "ok"
        // (the shell word-splits on the space and tries to run the first token only)
        let unquotedOutput = try? runShellCommand(scriptPath)
        XCTAssertNotEqual(
            unquotedOutput?.trimmingCharacters(in: .whitespacesAndNewlines), "ok",
            "unquoted path with a space should NOT produce 'ok'"
        )
    }

    // MARK: – Helper

    private func runShellCommand(_ cmd: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()   // swallow stderr
        try p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
