import AppKit
import SwiftUI

/// The dashboard quota palette. The menu bar uses a system-tinted template glyph.
enum MeterPalette {
    static let usedNS = NSColor(srgbRed: 0.91, green: 0.36, blue: 0.36, alpha: 1)
    static let remainingNS = NSColor(srgbRed: 0.18, green: 0.66, blue: 0.48, alpha: 1)
    static let used = Color(nsColor: usedNS)
    static let remaining = Color(nsColor: remainingNS)
}
