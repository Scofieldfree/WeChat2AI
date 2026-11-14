import AppKit
import SwiftUI

/// Editorial Sandstone. Native text and SwiftUI controls share these dynamic colors.
enum W2ATheme {
    enum Colors {
        static func adaptive(_ name: String, _ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
            NSColor(name: NSColor.Name("w2a-" + name)) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let value = isDark ? dark : light
                return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255,
                    alpha: isDark ? darkAlpha : lightAlpha)
            }
        }
        static let canvas = adaptive("bg-canvas", 0xFDFCFB, 0x141311)
        static let surface = adaptive("bg-surface", 0xF5F3EF, 0x1F1D1A)
        static let sidebar = adaptive("bg-sidebar", 0xEBE7E0, 0x181614)
        static let elevated = adaptive("bg-elevated", 0xFFFFFF, 0x26231F)
        static let hover = adaptive("bg-subtle-hover", 0x1C1917, 0xF5F3EF, lightAlpha: 0.04, darkAlpha: 0.06)
        static let selected = adaptive("bg-selected", 0xFDFCFB, 0x26231F)
        static let borderSubtle = adaptive("border-subtle", 0xE6E1D6, 0x26231F)
        static let border = adaptive("border-default", 0xDFDAD0, 0x2E2B26)
        static let borderStrong = adaptive("border-strong", 0xC7C0B3, 0x3E3A34)
        static let primaryText = adaptive("text-primary", 0x1C1917, 0xF5F3EF)
        static let secondaryText = adaptive("text-secondary", 0x57534E, 0xC7C2B8)
        static let mutedText = adaptive("text-muted", 0x78716C, 0x8C857B)
        static let onPrimary = adaptive("text-on-primary", 0xFDFCFB, 0x141311)
        static let primary = adaptive("primary-bg", 0x1C1917, 0xF5F3EF)
        static let primaryHover = adaptive("primary-hover", 0x2E2925, 0xFFFFFF)
        static let primaryActive = adaptive("primary-active", 0x0F0D0C, 0xDFDAD0)
        static let accent = adaptive("accent-clay", 0xC86446, 0xD47457)
        static let accentSoft = adaptive("accent-clay-soft", 0xF7EAE5, 0xD47457, darkAlpha: 0.16)
        static let focusRing = adaptive("focus-ring", 0xC86446, 0xD47457, lightAlpha: 0.35, darkAlpha: 0.45)
        static let success = adaptive("status-success", 0x3F7052, 0x528C67)
        static let successBackground = adaptive("status-success-bg", 0xEDF4F0, 0x528C67, darkAlpha: 0.15)
        static let warning = adaptive("status-warning", 0xB87D2B, 0xD1943E)
        static let warningBackground = adaptive("status-warning-bg", 0xFBF5EB, 0xD1943E, darkAlpha: 0.15)
        static let error = adaptive("status-error", 0xB84233, 0xD15647)
        static let errorBackground = adaptive("status-error-bg", 0xFDF2F0, 0xD15647, darkAlpha: 0.15)
    }
    enum TypeStyle {
        static let title = Font.system(size: 15, weight: .semibold)
        static let section = Font.system(size: 12, weight: .medium)
        static let body = Font.system(size: 14)
        static let metadata = Font.system(size: 11).monospacedDigit()
        static let emptyTitle = Font.system(size: 18, weight: .semibold)
        static let nativeBody = NSFont.systemFont(ofSize: 14)
        static let lineHeight: CGFloat = 23
        static let paragraphSpacing: CGFloat = 8
    }
    enum Space {
        static let xs: CGFloat = 4, sm: CGFloat = 8, md: CGFloat = 12
        static let lg: CGFloat = 16, xl: CGFloat = 20, panel: CGFloat = 24
    }
    enum Radius { static let small: CGFloat = 5, control: CGFloat = 6, card: CGFloat = 8, panel: CGFloat = 12 }
    enum Layout {
        static let initial = NSSize(width: 1180, height: 760)
        static let minimum = NSSize(width: 960, height: 620)
        static let toolbar: CGFloat = 52, detailHeader: CGFloat = 72, status: CGFloat = 28, dock: CGFloat = 92, readingWidth: CGFloat = 680, readingMinimum: CGFloat = 620
        static let sidebarMin: CGFloat = 200, sidebarIdeal: CGFloat = 220, sidebarMax: CGFloat = 260
        static let batchMin: CGFloat = 260, batchIdeal: CGFloat = 280, batchMax: CGFloat = 320
    }
    enum Motion { static let control = Animation.easeOut(duration: 0.14), panel = Animation.easeOut(duration: 0.20) }
}

extension Color {
    static let w2aCanvas = Color(nsColor: W2ATheme.Colors.canvas)
    static let w2aSurface = Color(nsColor: W2ATheme.Colors.surface)
    static let w2aSidebar = Color(nsColor: W2ATheme.Colors.sidebar)
    static let w2aElevated = Color(nsColor: W2ATheme.Colors.elevated)
    static let w2aText = Color(nsColor: W2ATheme.Colors.primaryText)
    static let w2aSecondary = Color(nsColor: W2ATheme.Colors.secondaryText)
    static let w2aAccent = Color(nsColor: W2ATheme.Colors.accent)
    static let w2aBorder = Color(nsColor: W2ATheme.Colors.border)
}
