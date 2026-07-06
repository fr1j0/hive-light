import AppKit
import HiveLightCore

/// Draws the fat traffic-light menu-bar glyph: a rounded-rectangle outline
/// housing with three squared bar lamps. Each lamp is lit independently via
/// its `LampMotion`; lamps with `.off` are dimmed `mono`. Non-template so
/// the lit color survives in the menu bar.
enum TrafficLightIcon {
    /// Lamp identity used only to look up the lit color; not the same as LampMotion.
    private enum IconLamp { case red, orange, green, off }

    /// Fixed glyph size in points (fat aspect, fits the ~18pt menu-bar height).
    static let size = NSSize(width: 15, height: 18)

    static func image(state: IconState, phase: Double, mono: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let stroke: CGFloat = 1.6
        let housing = NSRect(origin: .zero, size: size).insetBy(dx: stroke/2 + 0.5, dy: stroke/2 + 0.5)
        let radius = housing.width * 0.30
        let outline = NSBezierPath(roundedRect: housing, xRadius: radius, yRadius: radius)
        outline.lineWidth = stroke
        mono.setStroke()
        outline.stroke()

        let lamps: [(IconLamp, LampMotion)] = [(.red, state.red), (.orange, state.orange), (.green, state.green)]
        let innerTop = housing.maxY - housing.width * 0.20
        let innerBot = housing.minY + housing.width * 0.20
        let span = innerTop - innerBot
        let centers = [innerTop, (innerTop + innerBot) / 2, innerBot]
        let barW = housing.width * 0.60
        let barH = span / 3 * 0.78
        let barR = barH * 0.22

        for i in 0..<3 {
            let (lamp, motion) = lamps[i]
            let rect = NSRect(x: housing.midX - barW/2, y: centers[i] - barH/2, width: barW, height: barH)
            let fill = motion == .off
                ? mono.withAlphaComponent(0.28)
                : litColor(lamp).withAlphaComponent(CGFloat(litAlpha(for: motion, phase: phase)))
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: barR, yRadius: barR).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func litColor(_ lamp: IconLamp) -> NSColor {
        switch lamp {
        case .red:    return NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .off:    return .clear
        }
    }
}
