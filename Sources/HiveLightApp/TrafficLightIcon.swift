import AppKit
import HiveLightCore

/// Draws the traffic-light menu-bar glyph with battery-icon anatomy: a faded
/// white outer border, inner padding, and a near-black core plate carrying
/// three round lamps (padded off the core edges). One rendering for both
/// menu-bar appearances. Lit lamps are filled color dots; off lamps are
/// transparent holes punched through the core, so the menu bar shows through
/// as an empty socket. Non-template so the colors survive in the menu bar.
enum TrafficLightIcon {
    /// Lamp identity used only to look up the lit color; not the same as LampMotion.
    private enum IconLamp { case red, orange, green, off }

    /// Fixed glyph size in points (plate footprint comparable to neighboring
    /// status icons, fits the ~18pt menu-bar height).
    static let size = NSSize(width: 13, height: 18)

    static func image(state: IconState, phase: Double) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // Battery-icon anatomy: faded outer border, a breath of padding, then
        // a bright inner core carrying the lamps (padded off the core edges).
        // The core is bright, so lamps use the palette for the OPPOSITE
        // ground: deep colors on the white core of a dark bar, bright colors
        // on the dark core of a light bar.
        let housingW: CGFloat = 12.4
        let housing = NSRect(x: (size.width - housingW) / 2, y: 0, width: housingW, height: size.height)
            .insetBy(dx: 0.5, dy: 0.5)
        // Same rendering in both themes: faded white border, near-black core,
        // bright lamp palette.
        let border = NSBezierPath(roundedRect: housing, xRadius: 3.8, yRadius: 3.8)
        NSColor.white.withAlphaComponent(0.80).setStroke()
        border.lineWidth = 1.2
        border.stroke()

        let core = housing.insetBy(dx: 1.5, dy: 1.5)
        NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: core, xRadius: 2.5, yRadius: 2.5).fill()

        let lamps: [(IconLamp, LampMotion)] = [(.red, state.red), (.orange, state.orange), (.green, state.green)]
        let dotR: CGFloat = 1.8
        let step: CGFloat = 4.3
        let midY = size.height / 2
        let centers = [midY + step, midY, midY - step]

        for i in 0..<3 {
            let (lamp, motion) = lamps[i]
            let rect = NSRect(x: size.width / 2 - dotR, y: centers[i] - dotR, width: dotR * 2, height: dotR * 2)
            if motion == .off {
                // Hollow placeholder: punch a transparent hole through the
                // core so the menu bar shows through — an empty socket.
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.setBlendMode(.clear)
                    NSBezierPath(ovalIn: rect.insetBy(dx: 0.1, dy: 0.1)).fill()
                    ctx.restoreGState()
                }
            } else {
                let alpha = CGFloat(litAlpha(for: motion, phase: phase))
                let color = litColor(lamp)
                // Halo: zero-offset shadow in the lamp's own color makes the
                // lit dot bloom; it tracks the blink/breathe alpha.
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = color.withAlphaComponent(alpha)
                glow.shadowBlurRadius = 3.0
                glow.shadowOffset = .zero
                glow.set()
                color.withAlphaComponent(alpha).setFill()
                NSBezierPath(ovalIn: rect).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
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
