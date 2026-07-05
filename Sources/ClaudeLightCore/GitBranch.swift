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
