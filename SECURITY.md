# Security Policy

## Reporting a vulnerability

Please report security issues **privately**. Do not open a public issue.

**Preferred channel:** [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) — on this repo's **Security** tab, click **Report a vulnerability**. This opens a private draft advisory only the maintainer can see.

**Fallback:** if private reporting isn't available, email the address listed on the [maintainer's GitHub profile](https://github.com/fr1j0) with the subject line `claude-light: security`.

When reporting, include:

- the affected component (hook shim, session-state parsing, settings editing, app UI, release workflow);
- a minimal reproducer — a crafted session-state file, transcript snippet, or hook payload is ideal;
- the impact you observed, and a suggested fix if you have one.

## In scope

Claude Light runs on every Claude Code hook event and edits `~/.claude/settings.json` to install its hooks, so its security surface is taken seriously despite being small:

- **The hook shim** (`Sources/claude-light-hook/`) — anything that lets a session's content execute commands or escalate beyond writing state files.
- **Parsing of untrusted input** — session-state JSON in `~/.claude-light/sessions/`, transcript files, and hook payloads are attacker-influenced (a malicious repo or prompt can shape their contents). Crashes, spoofed UI, or code execution triggered through them qualify.
- **Settings editing** — bugs where hook install/removal corrupts or plants unexpected entries in `~/.claude/settings.json`.
- **Release integrity** — the GitHub Actions release workflow, published checksums, and the Homebrew cask (here and in the tap).

## Out of scope

- Claude Code itself, the Claude API, or Anthropic services — report those to [Anthropic](https://www.anthropic.com/responsible-disclosure-policy).
- Homebrew, macOS, or other third-party software.
- Modified or self-built binaries; only official [Releases](https://github.com/fr1j0/claude-light/releases) are supported.
- Anything requiring maintainer-level GitHub access to exploit.

## Supported versions

Only the latest release is supported. Security fixes ship forward as a new release, not as backports.
