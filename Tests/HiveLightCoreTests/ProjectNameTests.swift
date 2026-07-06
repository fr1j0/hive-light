import XCTest
@testable import HiveLightCore

final class ProjectNameTests: XCTestCase {
    func test_emptyCwd_isUnknown() {
        XCTAssertEqual(projectName(forCwd: ""), "unknown")
    }

    func test_normalProject_usesLastComponent() {
        XCTAssertEqual(projectName(forCwd: "/Users/me/Projects/hive-light"), "hive-light")
        XCTAssertEqual(projectName(forCwd: "/Users/me/Projects/hive-light/"), "hive-light")
    }

    func test_realFolderNamedT_staysT() {
        // A genuine project directory named "T" is not a temp path.
        XCTAssertEqual(projectName(forCwd: "/Users/me/Projects/T"), "T")
    }

    func test_macUserTempDir_isTemp() {
        XCTAssertEqual(projectName(forCwd: "/var/folders/b1/8gtjt5f56xl2ztn8mrglm4gc0000gn/T"), "temp")
        XCTAssertEqual(projectName(forCwd: "/var/folders/b1/8gtjt5f56xl2ztn8mrglm4gc0000gn/T/sub"), "temp")
        XCTAssertEqual(projectName(forCwd: "/private/var/folders/b1/8x/T"), "temp")
    }

    func test_tmp_isTemp() {
        XCTAssertEqual(projectName(forCwd: "/tmp"), "temp")
        XCTAssertEqual(projectName(forCwd: "/tmp/scratch"), "temp")
        XCTAssertEqual(projectName(forCwd: "/private/tmp/scratch"), "temp")
    }

    func test_varFoldersCache_isNotTemp() {
        // The cache dir (C) under /var/folders is not the temp-items dir (T).
        XCTAssertEqual(projectName(forCwd: "/var/folders/b1/8x/C/something"), "something")
    }
}
