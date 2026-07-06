import Foundation

public enum LampMotion: String, Sendable, Equatable {
    case off, steady, blink, breathe
}

/// Per-lamp motion for the traffic-light icon. Red and orange can be lit at the
/// same time (error + running); green lights only as the resting baseline.
public struct IconState: Sendable, Equatable {
    public let red: LampMotion      // off | steady | blink
    public let orange: LampMotion   // off | breathe
    public let green: LampMotion    // off | steady
    public init(red: LampMotion, orange: LampMotion, green: LampMotion) {
        self.red = red
        self.orange = orange
        self.green = green
    }
    /// True when any lamp needs the animation clock running.
    public var isAnimating: Bool { red == .blink || orange == .breathe }
}

/// Model B: today's single aggregate lamp (red > orange > green) with `error`
/// layered on additively as a blinking red that does NOT suppress the base.
/// Handoff (review requested) is a base-red like waiting: steady, never blink.
public func iconState(for sessions: [Session]) -> IconState {
    let hasError = sessions.contains { $0.status == .error }
    let hasAttention = sessions.contains { $0.status == .attention }
    let hasWaiting = sessions.contains { $0.status == .waiting }
    let hasHandoff = sessions.contains { $0.status == .handoff }
    let hasRunning = sessions.contains { $0.status == .running }
    let hasIdle = sessions.contains { $0.status == .idle }

    let baseRed = hasWaiting || hasHandoff
    let red: LampMotion = (hasError || hasAttention) ? .blink : (baseRed ? .steady : .off)
    // Orange is suppressed by a base-red (waiting/handoff/attention) but NOT by error.
    let orange: LampMotion = (hasRunning && !baseRed && !hasAttention) ? .breathe : .off
    // Green only when nothing else is active at all.
    let green: LampMotion = (hasIdle && !hasError && !hasRunning && !baseRed && !hasAttention) ? .steady : .off

    return IconState(red: red, orange: orange, green: green)
}

/// Alpha for a lamp with the given motion at `phase` seconds. Pure so it is
/// unit-testable; the app advances `phase` via a timer.
public func litAlpha(for motion: LampMotion, phase: Double) -> Double {
    switch motion {
    case .off:
        return 0.0
    case .steady:
        return 1.0
    case .blink:
        let t = phase.truncatingRemainder(dividingBy: 0.6)
        return t < 0.3 ? 1.0 : 0.2
    case .breathe:
        let cycle = phase.truncatingRemainder(dividingBy: 1.5) / 1.5     // 0..1
        let c = cos(2 * Double.pi * cycle)                                // 1 → -1
        return 0.55 + 0.45 * (0.5 + 0.5 * c)                              // 1.0 … 0.55
    }
}
