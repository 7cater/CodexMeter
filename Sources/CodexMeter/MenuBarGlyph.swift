import AppKit
import CodexMeterCore

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case doubleRings, concentricRings, stackedRings, bars
    var id: String { rawValue }
    var title: String {
        switch self {
        case .doubleRings: return "并排双圆环"
        case .concentricRings: return "内嵌圆环"
        case .stackedRings: return "上下双圆环"
        case .bars: return "用量条"
        }
    }
    func legend(onlyFive: Bool) -> String {
        if onlyFive { return "仅显示 5h 额度" }
        switch self {
        case .doubleRings: return "左侧 5h · 右侧 7d"
        case .concentricRings: return "外环 5h · 内环 7d"
        case .stackedRings, .bars: return "上排 5h · 下排 7d"
        }
    }
}

/// A template glyph: macOS supplies the foreground color for light/dark menu bars
/// and highlighted buttons. Solid alpha shows used quota; a faint track is remaining.
enum MenuBarGlyph {
    static func image(five: RateWindow?, seven: RateWindow?, onlyFive: Bool,
                      style: MenuBarStyle = .doubleRings) -> NSImage {
        let width: CGFloat
        if style == .bars { width = 46 }
        else if onlyFive || style == .concentricRings { width = 22 }
        else { width = style == .stackedRings ? 30 : 40 }
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)

            func ring(center: CGPoint, radius: CGFloat, lineWidth: CGFloat, window: RateWindow?) {
                context.saveGState()
                defer { context.restoreGState() }
                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.setLineWidth(lineWidth)
                context.setLineCap(.round)
                guard let window else {
                    context.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
                    context.setLineDash(phase: 0, lengths: [1.5, 2])
                    context.strokeEllipse(in: rect)
                    return
                }
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.22).cgColor)
                context.strokeEllipse(in: rect)
                let fraction = window.usedFraction
                guard fraction > 0 else { return }
                context.setStrokeColor(NSColor.black.cgColor)
                if fraction == 1 {
                    // A closed circle avoids a seam or overlapping end caps at 100%.
                    context.strokeEllipse(in: rect)
                } else {
                    context.addArc(center: center, radius: radius, startAngle: .pi / 2,
                                   endAngle: .pi / 2 - 2 * .pi * fraction, clockwise: true)
                    context.strokePath()
                }
            }

            func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
                (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
                    .foregroundColor: NSColor.black
                ])
            }

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
            if style == .bars {
                if onlyFive { meter(label: "5h", y: 9, window: five) }
                else {
                    meter(label: "5h", y: 14, window: five)
                    meter(label: "7d", y: 4, window: seven)
                }
            } else if onlyFive {
                ring(center: CGPoint(x: 11, y: 11), radius: 8.5, lineWidth: 2.2, window: five)
            } else {
                switch style {
                case .doubleRings:
                    ring(center: CGPoint(x: 10, y: 11), radius: 7.5, lineWidth: 2.2, window: five)
                    ring(center: CGPoint(x: 30, y: 11), radius: 7.5, lineWidth: 2.2, window: seven)
                case .concentricRings:
                    ring(center: CGPoint(x: 11, y: 11), radius: 8.5, lineWidth: 2, window: five)
                    ring(center: CGPoint(x: 11, y: 11), radius: 4.8, lineWidth: 2, window: seven)
                case .stackedRings:
                    ring(center: CGPoint(x: 6.5, y: 16), radius: 3.8, lineWidth: 1.5, window: five)
                    ring(center: CGPoint(x: 6.5, y: 6), radius: 3.8, lineWidth: 1.5, window: seven)
                    label("5h", x: 14, y: 12, size: 8.5)
                    label("7d", x: 14, y: 2, size: 8.5)
                case .bars: break
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
