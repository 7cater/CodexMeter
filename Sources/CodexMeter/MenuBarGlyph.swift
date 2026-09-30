import AppKit
import CodexMeterCore

/// A template glyph: macOS supplies the foreground color for light/dark menu bars
/// and highlighted buttons. Solid alpha shows used quota; a faint track is remaining.
enum MenuBarGlyph {
    static func image(five: RateWindow?, seven: RateWindow?, onlyFive: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 46, height: 22), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            func meter(label: String, y: CGFloat, window: RateWindow?) {
                let labelY = y - (onlyFive ? 4 : 3)
                (label as NSString).draw(at: NSPoint(x: 1, y: labelY), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: onlyFive ? 10 : 8.5, weight: .medium),
                    .foregroundColor: NSColor.black
                ])
                let rect = CGRect(x: 21, y: y, width: 24, height: 4)
                let track = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
                context.saveGState()
                defer { context.restoreGState() }
                guard let window else {
                    // Missing data has a dashed outline rather than looking like 0% used.
                    context.addPath(track)
                    context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
                    context.setLineWidth(0.75)
                    context.setLineDash(phase: 0, lengths: [2, 2])
                    context.strokePath()
                    return
                }
                context.addPath(track)
                context.setFillColor(NSColor.black.withAlphaComponent(0.22).cgColor)
                context.fillPath()
                if window.usedFraction > 0 {
                    context.addPath(track)
                    context.clip()
                    context.setFillColor(NSColor.black.cgColor)
                    context.fill(CGRect(x: rect.minX, y: rect.minY,
                                        width: rect.width * window.usedFraction, height: rect.height))
                }
            }
            if onlyFive { meter(label: "5h", y: 9, window: five) }
            else {
                meter(label: "5h", y: 14, window: five)
                meter(label: "7d", y: 4, window: seven)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
