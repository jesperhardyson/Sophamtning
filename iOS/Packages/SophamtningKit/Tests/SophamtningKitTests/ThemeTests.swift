import Foundation
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

    @Test func okandFraktionAnvanderGiltigHexSomFarg() {
        #expect(FractionStyle(id: "tradgard", info: info("recycle", color: "#336699")).usesAPIColor)
        #expect(!FractionStyle(id: "tradgard", info: info("recycle", color: "grön")).usesAPIColor)
        #expect(!FractionStyle(id: "tradgard", info: info("recycle", color: "#12345")).usesAPIColor)
        #expect(!FractionStyle(id: "rest", info: info("trash-2", color: "#336699")).usesAPIColor)
    }

    @Test func fargtokenFinnsILjustOchMorkt() {
        #expect(ThemeToken.primary.light == 0x157A46)
        #expect(ThemeToken.primary.dark == 0x4CC384)
        #expect(ThemeToken.bg.light == 0xE8F2EA)
        #expect(ThemeToken.fracPlastBg.dark == 0x3D241B)
        #expect(ThemeToken.allCases.count == 28)
    }

    @Test func hexTolkas() {
        #expect(parseHexColor("#157A46") == 0x157A46)
        #expect(parseHexColor("157A46") == nil)
        #expect(parseHexColor("#GGGGGG") == nil)
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
