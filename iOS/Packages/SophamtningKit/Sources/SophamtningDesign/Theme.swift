import SwiftUI

/// Färgvariablerna i designen, med ett värde för ljust och ett för mörkt läge (RGB som 0xRRGGBB).
public enum ThemeToken: CaseIterable, Sendable {
    case bg, surface, surface2, border, text, text2
    case primary, onPrimary
    case brand, brandSoft, brandText
    case earth, earthSoft
    case warn, warnBg
    case fracRest, fracRestBg, fracMat, fracMatBg, fracPapper, fracPapperBg
    case fracPlast, fracPlastBg, fracGlas, fracGlasBg, fracMetall, fracMetallBg
    case cardOverlay

    public var light: UInt32 { values.light }
    public var dark: UInt32 { values.dark }

    /// Genomskinlighet, 1 för alla utom `cardOverlay`.
    public var lightAlpha: Double { self == .cardOverlay ? 0x26 / 255.0 : 1 }
    public var darkAlpha: Double { self == .cardOverlay ? 0x1F / 255.0 : 1 }

    private var values: (light: UInt32, dark: UInt32) {
        switch self {
        case .bg: (0xE8F2EA, 0x0C1A12)
        case .surface: (0xFFFFFF, 0x14241A)
        case .surface2: (0xDCEBDF, 0x1C2F23)
        case .border: (0xCCDFD0, 0x28402F)
        case .text: (0x1B231F, 0xEDF2EE)
        case .text2: (0x526158, 0xA0B3A6)
        case .primary: (0x157A46, 0x4CC384)
        case .onPrimary: (0xFFFFFF, 0x0B2416)
        case .brand: (0x1FA35C, 0x4CC384)
        case .brandSoft: (0xCFEBD8, 0x1A3D28)
        case .brandText: (0x12673B, 0x8FE0B2)
        case .earth: (0x8A5A2B, 0xD9A06A)
        case .earthSoft: (0xF3EADF, 0x2E241A)
        case .warn: (0x9A4A00, 0xF4B56A)
        case .warnBg: (0xFDEFD9, 0x3A2914)
        case .fracRest: (0x474C48, 0xC3C9C4)
        case .fracRestBg: (0xE9EAE7, 0x2A2F2C)
        case .fracMat: (0x7A4A1E, 0xE0A873)
        case .fracMatBg: (0xF3E6D8, 0x3A2C1F)
        case .fracPapper: (0x2E5E86, 0x8DB6DE)
        case .fracPapperBg: (0xE1EAF3, 0x1C2A38)
        case .fracPlast: (0xA8431F, 0xF0906C)
        case .fracPlastBg: (0xFAE6DD, 0x3D241B)
        case .fracGlas: (0x1F6A7A, 0x72C6D6)
        case .fracGlasBg: (0xDDEFF2, 0x173238)
        case .fracMetall: (0x6B4F7A, 0xC6A9D6)
        case .fracMetallBg: (0xEEE6F1, 0x2E2436)
        case .cardOverlay: (0xFFFFFF, 0x0B2416)
        }
    }

    public var color: Color {
        Color(light: light, lightAlpha: lightAlpha, dark: dark, darkAlpha: darkAlpha)
    }
}

extension Color {
    /// Designens färger. Alla följer ljust och mörkt läge.
    public enum Theme {
        public static let bg = ThemeToken.bg.color
        public static let surface = ThemeToken.surface.color
        public static let surface2 = ThemeToken.surface2.color
        public static let border = ThemeToken.border.color
        public static let text = ThemeToken.text.color
        public static let text2 = ThemeToken.text2.color
        public static let primary = ThemeToken.primary.color
        public static let onPrimary = ThemeToken.onPrimary.color
        public static let brand = ThemeToken.brand.color
        public static let brandSoft = ThemeToken.brandSoft.color
        public static let brandText = ThemeToken.brandText.color
        public static let earth = ThemeToken.earth.color
        public static let earthSoft = ThemeToken.earthSoft.color
        public static let warn = ThemeToken.warn.color
        public static let warnBg = ThemeToken.warnBg.color
        public static let fracRest = ThemeToken.fracRest.color
        public static let fracRestBg = ThemeToken.fracRestBg.color
        public static let fracMat = ThemeToken.fracMat.color
        public static let fracMatBg = ThemeToken.fracMatBg.color
        public static let fracPapper = ThemeToken.fracPapper.color
        public static let fracPapperBg = ThemeToken.fracPapperBg.color
        public static let fracPlast = ThemeToken.fracPlast.color
        public static let fracPlastBg = ThemeToken.fracPlastBg.color
        public static let fracGlas = ThemeToken.fracGlas.color
        public static let fracGlasBg = ThemeToken.fracGlasBg.color
        public static let fracMetall = ThemeToken.fracMetall.color
        public static let fracMetallBg = ThemeToken.fracMetallBg.color
        public static let cardOverlay = ThemeToken.cardOverlay.color
    }

    /// En färg som byter värde mellan ljust och mörkt läge, på både iOS och macOS.
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(rgb: dark, alpha: darkAlpha)
                : NSColor(rgb: light, alpha: lightAlpha)
        })
        #endif
    }

}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
#endif
