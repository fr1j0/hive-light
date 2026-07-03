import SwiftUI
import AppKit
import ClaudeLightCore

struct MenuContent: View {
    @ObservedObject var watcher: SessionWatcher

    var body: some View {
        if watcher.sessions.isEmpty {
            Text("No active Claude Code sessions").foregroundStyle(.secondary)
        } else {
            if let summary = watcher.summary {
                Label {
                    Text(summary)
                } icon: {
                    Image(nsImage: Self.dot(headerColor))
                }
                .disabled(true)
                Divider()
            }
            ForEach(watcher.sessions, id: \.sessionID) { session in
                Button {
                    TerminalFocuser.focus(session)
                } label: {
                    Label {
                        Text(rowText(for: session))
                    } icon: {
                        if session.status == .error {
                            Image(nsImage: Self.warningTriangle())
                        } else {
                            Image(nsImage: Self.dot(color(for: session.status)))
                        }
                    }
                }
                if let list = watcher.subagentsBySession[session.sessionID] {
                    // Subagents share the parent session's terminal, so their rows are
                    // status-only (non-interactive) — the parent row is the single pointer.
                    ForEach(list.visible, id: \.id) { subagent in
                        Label {
                            Text(subagent.label)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        } icon: {
                            // Only a failure is marked; running rows carry a
                            // transparent spacer so their titles stay aligned.
                            Image(nsImage: subagent.state == .failed
                                  ? Self.subagentFailedIcon : Self.subagentBlankIcon)
                        }
                    }
                    if list.overflowRunning > 0 {
                        Label {
                            Text("+\(list.overflowRunning) more running")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        } icon: {
                            Image(nsImage: Self.subagentBlankIcon)
                        }
                    }
                }
            }
        }
        Divider()
        // A Button (not a Toggle) so the menu doesn't reserve a checkmark "state"
        // column — that column is what pushes every icon/dot right. We show the
        // on/off state with a checkbox glyph in the same icon column as the others.
        Button {
            watcher.showSubagents.toggle()
        } label: {
            Label("Show subagents",
                  systemImage: watcher.showSubagents ? "checkmark.square.fill" : "square")
        }
        Button {
            if watcher.hooksInstalled {
                watcher.removeHooks()
            } else {
                watcher.installHooks()
            }
        } label: {
            Label(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks",
                  systemImage: "link")
        }
        if let hookError = watcher.hookActionError {
            Label {
                Text(hookError)
                    .font(.system(size: 11))
            } icon: {
                Image(nsImage: Self.warningTriangle())
            }
            .disabled(true)
        }
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Claude Light", systemImage: "power")
        }
        if let version = Self.appVersion {
            Divider()
            Text("Claude Light v\(version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    /// The running app's marketing version (CFBundleShortVersionString), e.g. "0.4.0".
    private static let appVersion: String? =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    /// Indent (points) applied to subagent rows so their marker sits right of the
    /// parent's — menus place the icon at a fixed x, so we bake the inset into the image.
    static let subagentIndent: CGFloat = 16

    /// Smaller warning triangle for indented subagent rows (parent triangle is 11pt).
    static let subagentTrianglePointSize: CGFloat = 9

    /// The only marked subagent state: a failure. Running rows use a same-size
    /// transparent spacer so every subagent title lines up under the parent.
    private static let subagentFailedIcon = warningTriangle(
        leadingInset: subagentIndent, pointSize: subagentTrianglePointSize)
    private static let subagentBlankIcon: NSImage = {
        let img = NSImage(size: subagentFailedIcon.size)
        img.lockFocus(); img.unlockFocus()   // materialize a transparent rep of the right size
        img.isTemplate = false
        return img
    }()

    /// Filled colored dot as a NON-template image (menus coerce templates to mono).
    private static func dot(_ color: NSColor) -> NSImage {
        let d: CGFloat = 9
        let image = NSImage(size: NSSize(width: d, height: d))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: d, height: d)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Red-tinted `exclamationmark.triangle.fill`, non-template. `leadingInset`
    /// prepends transparent space to indent the whole row; smaller `pointSize`
    /// marks a child (subagent) row.
    private static func warningTriangle(leadingInset: CGFloat = 0, pointSize: CGFloat = 11) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let base = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "error")?
            .withSymbolConfiguration(cfg) ?? NSImage()
        let out = NSImage(size: NSSize(width: base.size.width + leadingInset, height: base.size.height))
        out.lockFocus()
        base.draw(at: NSPoint(x: leadingInset, y: 0), from: .zero, operation: .sourceOver, fraction: 1)
        red.set()
        NSRect(x: leadingInset, y: 0, width: base.size.width, height: base.size.height).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    private var headerColor: NSColor {
        if watcher.icon.red != .off { return Self.red }
        if watcher.icon.orange != .off { return Self.orange }
        if watcher.icon.green != .off { return Self.green }
        return .secondaryLabelColor
    }

    private func rowText(for session: Session) -> String {
        if session.status == .error {
            let reason = watcher.errorReasons[session.sessionID] ?? "api error"
            return "\(session.project) — API error: \(reason)"
        }
        return "\(session.project) — \(friendlyLabel(for: session.status))"
    }

    private func color(for status: SessionStatus) -> NSColor {
        switch status {
        case .waiting, .attention, .handoff, .error: return Self.red
        case .running: return Self.orange
        case .idle: return Self.green
        }
    }

    private func friendlyLabel(for status: SessionStatus) -> String {
        switch status {
        case .running: return "running"
        case .waiting: return "waiting for permission"
        case .attention: return "awaiting your reply"
        case .handoff: return "review requested"
        case .idle: return "idle"
        case .error: return "API error"
        }
    }

    private static let red = NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
    private static let orange = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
    private static let green = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
}
