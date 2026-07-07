import Foundation

/// Branch name for the git checkout containing `cwd`, or nil for non-repos,
/// detached HEAD, and unreadable layouts. Walks parents to the nearest
/// `.git`, then reads HEAD directly — one file read per level, never a
/// subprocess (hook perf, #43).
public func gitBranch(forCwd cwd: String) -> String? {
    guard !cwd.isEmpty else { return nil }
    var dir = URL(fileURLWithPath: cwd).standardizedFileURL
    while true {
        let dotGit = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
            // A `.git` FILE marks a worktree/submodule: follow its gitdir pointer.
            guard let gitDir = isDir.boolValue ? dotGit : resolveGitdirFile(dotGit),
                  let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"),
                                         encoding: .utf8)
            else { return nil }
            return parseGitHead(head)
        }
        if dir.path == "/" { return nil }
        dir = dir.deletingLastPathComponent()
    }
}

/// Identity of the repository containing `cwd` — the MAIN checkout's root,
/// unifying worktrees and submodules with their parent repo (the panel's
/// grouping key; stable-session-order spec). Same parent-walk as
/// `gitBranch`, one file read per level, never a subprocess. Nil for
/// non-repos.
public func gitRepoRoot(forCwd cwd: String) -> String? {
    guard !cwd.isEmpty else { return nil }
    var dir = URL(fileURLWithPath: cwd).standardizedFileURL
    while true {
        let dotGit = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
            if isDir.boolValue { return dir.path }
            // Worktree/submodule: the resolved gitdir lives under the main
            // repo's .git — its prefix names the main root.
            guard let gitDir = resolveGitdirFile(dotGit) else { return dir.path }
            // Worktree gitdir pointers are absolute paths; renaming the
            // parent repo folder leaves them dangling. A dead pointer must
            // not become the grouping key — fall back to this checkout.
            guard FileManager.default.fileExists(atPath: gitDir.standardizedFileURL.path) else {
                return dir.path
            }
            let path = gitDir.standardizedFileURL.path
            if let range = path.range(of: "/.git/") { return String(path[..<range.lowerBound]) }
            if path.hasSuffix("/.git") { return String(path.dropLast("/.git".count)) }
            return dir.path   // unrecognized layout: the checkout itself
        }
        if dir.path == "/" { return nil }
        dir = dir.deletingLastPathComponent()
    }
}

/// "ref: refs/heads/<branch>" → branch (slashes preserved). Anything else —
/// detached SHA, tag ref, empty — is nil.
func parseGitHead(_ contents: String) -> String? {
    let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "ref: refs/heads/"
    guard line.hasPrefix(prefix) else { return nil }
    let name = String(line.dropFirst(prefix.count))
    return name.isEmpty ? nil : name
}

/// A worktree/submodule `.git` file holds "gitdir: <path>"; relative paths
/// resolve against the file's directory.
func resolveGitdirFile(_ file: URL) -> URL? {
    guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    let line = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    guard line.hasPrefix("gitdir:") else { return nil }
    let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
    guard !path.isEmpty else { return nil }
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    return URL(fileURLWithPath: path, relativeTo: file.deletingLastPathComponent())
        .standardizedFileURL
}
