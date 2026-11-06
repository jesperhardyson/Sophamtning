import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import Testing
@testable import SophamtningDesign
import SophamtningKit

@Suite struct ThemeTests {
    private func info(_ icon: String, color: String = "#123456") -> FractionInfo {
        FractionInfo(name: "Namn", short: "N", color: color, icon: icon)
    }

    @Test func kandaFraktionerHarFargOchIkon() {
        let icons = ["rest": "trash-2", "mat": "apple", "papper": "package", "plast": "cup-soda",
                     "glas": "wine", "metall": "cylinder", "tidningar": "newspaper", "karl": "container"]
        for (id, icon) in icons {
            let style = FractionStyle(id: id, info: info(icon))
            #expect(style.isKnown, "\(id) ska vara känd")
            #expect(style.iconName == icon, "\(id) ska behålla sin ikon")
        }
    }

    @Test func okandFraktionFarNeutralIkon() {
        let style = FractionStyle(id: "tradgard", info: info("leaf-som-saknas"))
        #expect(style.iconName == "recycle")
        #expect(!style.isKnown)
    }

    @Test func okandFraktionFarNeutralStilOavsettAPIFarg() {
        let neutral = FractionStyle(id: "tradgard", info: info("recycle", color: "#336699"))
        let other = FractionStyle(id: "tradgard", info: info("recycle", color: "#FF0000"))
        for dark in [false, true] {
            #expect(resolved(neutral.foreground, dark: dark) == resolved(other.foreground, dark: dark))
            #expect(resolved(neutral.background, dark: dark) == resolved(other.background, dark: dark))
        }
        #expect(resolved(neutral.foreground, dark: false) == ThemeToken.text2.light)
        #expect(resolved(neutral.foreground, dark: true) == ThemeToken.text2.dark)
        #expect(resolved(neutral.background, dark: false) == ThemeToken.surface2.light)
        #expect(resolved(neutral.background, dark: true) == ThemeToken.surface2.dark)
    }

    @Test func fargtokenFinnsILjustOchMorkt() {
        #expect(ThemeToken.primary.light == 0x157A46)
        #expect(ThemeToken.primary.dark == 0x4CC384)
        #expect(ThemeToken.bg.light == 0xE8F2EA)
        #expect(ThemeToken.fracPlastBg.dark == 0x3D241B)
        #expect(ThemeToken.allCases.count == 28)
    }

    @Test func kandFraktionAnvanderTematsIkonInteAPIts() {
        #expect(FractionStyle(id: "glas", info: info("recycle")).iconName == "wine")
        #expect(FractionStyle(id: "rest", info: info("wine")).iconName == "trash-2")
        #expect(FractionStyle(id: "tradgard", info: info("wine")).iconName == "wine")
    }

    // Kontrast enligt WCAG.
    private func luminance(_ rgb: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((rgb >> 16) & 0xFF) + 0.7152 * channel((rgb >> 8) & 0xFF) + 0.0722 * channel(rgb & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    @Test func okandFraktionHarLasbarKontrastILjustOchMorkt() {
        let fg = FractionStyle.unknownForeground, bg = FractionStyle.unknownBackground
        #expect(contrast(fg.light, bg.light) >= 4.5)
        #expect(contrast(fg.dark, bg.dark) >= 4.5)
    }

    @Test func kandaFraktionerHarLasbarKontrast() {
        let pairs: [(ThemeToken, ThemeToken)] = [
            (.fracRest, .fracRestBg), (.fracMat, .fracMatBg), (.fracPapper, .fracPapperBg),
            (.fracPlast, .fracPlastBg), (.fracGlas, .fracGlasBg), (.fracMetall, .fracMetallBg),
        ]
        for (fg, bg) in pairs {
            #expect(contrast(fg.light, bg.light) >= 4.5, "\(fg) ljust")
            #expect(contrast(fg.dark, bg.dark) >= 4.5, "\(fg) mörkt")
        }
    }

    /// Löser en `Color` till 0xRRGGBB i ljust eller mörkt läge.
    private func resolved(_ color: Color, dark: Bool) -> UInt32? {
        #if canImport(UIKit)
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let ui = UIColor(color).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
        #else
        var result: UInt32?
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
            result = (UInt32((c.redComponent * 255).rounded()) << 16)
                | (UInt32((c.greenComponent * 255).rounded()) << 8)
                | UInt32((c.blueComponent * 255).rounded())
        }
        return result
        #endif
    }

    @Test func colorLosesVerkligenOlikaILjustOchMorkt() {
        for token in ThemeToken.allCases where token != .cardOverlay {
            #expect(resolved(token.color, dark: false) == token.light, "\(token) ljust")
            #expect(resolved(token.color, dark: true) == token.dark, "\(token) mörkt")
        }
        #expect(resolved(Color.Theme.primary, dark: false) != resolved(Color.Theme.primary, dark: true))
    }

    @Test func ikonerFinnsIPaketet() {
        #expect(FractionStyle.bundledIcons.count == 9)
        #expect(FractionStyle.bundledIcons.contains("recycle"))
        // Ikonerna ligger i en kompilerad asset catalog i paketets resurser.
        #expect(Fonts.bundle.url(forResource: "Assets", withExtension: "car") != nil)
        #if canImport(AppKit)
        for name in FractionStyle.bundledIcons {
            #expect(Fonts.bundle.image(forResource: NSImage.Name(name)) != nil, "\(name) saknas i asset catalog")
        }
        #endif
    }

    @Test func kortOverlayHarAlfa() {
        #expect(ThemeToken.cardOverlay.light == 0xFFFFFF)
        #expect(ThemeToken.cardOverlay.lightAlpha == 0x26 / 255.0)
        #expect(ThemeToken.cardOverlay.darkAlpha == 0x1F / 255.0)
        #expect(ThemeToken.primary.lightAlpha == 1)
    }

    @Test func typsnittenRegistrerasOchSaknasInteKrasch() {
        #expect(Fonts.register())
        #expect(Fonts.register())
    }

    @Test func kalenderTextFranSwedishFormat() throws {
        let day = try #require(DayDate("2026-11-09"))
        #expect(SwedishFormat.monthUppercased(day) == "NOV")
        #expect(SwedishFormat.dayNumber(day) == "9")
        #expect(SwedishFormat.weekdayName(day) == "måndag")
    }
}
