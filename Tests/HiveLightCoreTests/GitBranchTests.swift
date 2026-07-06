import XCTest
@testable import HiveLightCore

final class GitBranchTests: XCTestCase {
    // MARK: – parseGitHead

    func test_parseHead_normalRef() {
        XCTAssertEqual(parseGitHead("ref: refs/heads/main\n"), "main")
    }

    func test_parseHead_nestedBranchName_slashesPreserved() {
        XCTAssertEqual(parseGitHead("ref: refs/heads/feat/branch-labels\n"), "feat/branch-labels")
    }

    func test_parseHead_detachedSHA_isNil() {
        XCTAssertNil(parseGitHead("2e117d43b3bd541e5d5a0a77e58c2d78784ee283\n"))
    }

    func test_parseHead_malformed_isNil() {
        XCTAssertNil(parseGitHead("ref: refs/tags/v1.0\n"))
        XCTAssertNil(parseGitHead(""))
        XCTAssertNil(parseGitHead("ref: refs/heads/\n"))
    }

    // MARK: – discovery fixtures

    /// Builds a fake repo layout under a unique tmp root; returns the root.
    private func makeTree(_ files: [String: String], dirs: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("hive-light-git-\(UUID().uuidString)")
        for dir in dirs {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    func test_branch_atRepoRoot() throws {
        let root = try makeTree(["repo/.git/HEAD": "ref: refs/heads/main\n"])
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("repo").path), "main")
    }

    func test_branch_fromNestedSubdirectory() throws {
        let root = try makeTree(["repo/.git/HEAD": "ref: refs/heads/fix/x\n"],
                                dirs: ["repo/Sources/Deep"])
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("repo/Sources/Deep").path),
                       "fix/x")
    }

    func test_nonRepo_isNil() throws {
        let root = try makeTree([:], dirs: ["plain/dir"])
        XCTAssertNil(gitBranch(forCwd: root.appendingPathComponent("plain/dir").path))
    }

    func test_worktree_gitdirFile_absolutePath() throws {
        let root = try makeTree([:], dirs: ["wt"])
        let gitdir = try makeTree(["worktrees/wt/HEAD": "ref: refs/heads/feat/wt\n"])
        try "gitdir: \(gitdir.appendingPathComponent("worktrees/wt").path)\n"
            .write(to: root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("wt").path), "feat/wt")
    }

    func test_worktree_gitdirFile_relativePath() throws {
        let root = try makeTree(["actual/HEAD": "ref: refs/heads/rel\n"], dirs: ["wt"])
        try "gitdir: ../actual\n"
            .write(to: root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(gitBranch(forCwd: root.appendingPathComponent("wt").path), "rel")
    }

    func test_missingHEAD_isNil() throws {
        let root = try makeTree([:], dirs: ["repo/.git"])
        XCTAssertNil(gitBranch(forCwd: root.appendingPathComponent("repo").path))
    }

    func test_emptyCwd_isNil() {
        XCTAssertNil(gitBranch(forCwd: ""))
    }

    // MARK: – gitRepoRoot (session grouping identity)

    func test_repoRoot_normalRepo_isDotGitParent() throws {
        let root = try makeTree(["repo/.git/HEAD": "ref: refs/heads/main\n"])
        let repo = root.appendingPathComponent("repo").path
        XCTAssertEqual(gitRepoRoot(forCwd: repo), repo)
    }

    func test_repoRoot_subdirectory_resolvesToRoot() throws {
        let root = try makeTree(["repo/.git/HEAD": "ref: refs/heads/main\n"],
                                dirs: ["repo/src/deep"])
        let repo = root.appendingPathComponent("repo").path
        XCTAssertEqual(gitRepoRoot(forCwd: repo + "/src/deep"), repo)
    }

    func test_repoRoot_worktree_unifiesWithMainRepo() throws {
        // Worktree .git FILE points into <main>/.git/worktrees/<name> —
        // the group identity is the MAIN repo, so worktree sessions cluster
        // with their parent checkout.
        let root = try makeTree([
            "main/.git/worktrees/wt/HEAD": "ref: refs/heads/feat/x\n",
        ])
        let mainRepo = root.appendingPathComponent("main").path
        let wt = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: wt, withIntermediateDirectories: true)
        try "gitdir: \(mainRepo)/.git/worktrees/wt\n"
            .write(to: wt.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertEqual(gitRepoRoot(forCwd: wt.path), mainRepo)
    }

    func test_repoRoot_nonRepo_isNil() throws {
        let root = try makeTree([:], dirs: ["plain"])
        XCTAssertNil(gitRepoRoot(forCwd: root.appendingPathComponent("plain").path))
        XCTAssertNil(gitRepoRoot(forCwd: ""))
    }
}
