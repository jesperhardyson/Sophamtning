import Foundation
import Testing
@testable import SophamtningDesign

@Suite struct StartIntroTests {
    // MARK: Tidslinjen

    @Test func langdenArHogst08Sekunder() {
        #expect(StartIntroTimeline.duration(reduceMotion: false) <= 0.8)
        #expect(StartIntroTimeline.duration(reduceMotion: true) <= 0.8)
    }

    @Test func forstaBildenLiggerSomStartskarmen() {
        // Startskärmen visar logotypen i naturlig storlek, utan toning, på appens bakgrundsfärg.
        for reduce in [false, true] {
            let frame = StartIntroTimeline.frame(at: 0, reduceMotion: reduce)
            #expect(frame == StartIntroTimeline.Frame(scale: 1, logoOpacity: 1, backgroundOpacity: 1), "reduce \(reduce)")
        }
        // Tid före start ger samma bild.
        #expect(StartIntroTimeline.frame(at: -1, reduceMotion: false) == StartIntroTimeline.frame(at: 0, reduceMotion: false))
    }

    @Test func slutbildenArHelTransparent() {
        for reduce in [false, true] {
            let end = StartIntroTimeline.duration(reduceMotion: reduce)
            let frame = StartIntroTimeline.frame(at: end, reduceMotion: reduce)
            #expect(frame.logoOpacity == 0, "reduce \(reduce)")
            #expect(frame.backgroundOpacity == 0, "reduce \(reduce)")
            #expect(StartIntroTimeline.frame(at: end + 5, reduceMotion: reduce) == frame)
        }
    }

    @Test func logotypenKrymperOchTonasUtEfterHallet() {
        let mid = StartIntroTimeline.frame(at: 0.5, reduceMotion: false)
        #expect(mid.scale < 1 && mid.scale > StartIntroTimeline.finalScale)
        #expect(mid.logoOpacity > 0 && mid.logoOpacity < 1)
        #expect(mid.backgroundOpacity > 0 && mid.backgroundOpacity < 1)
        #expect(StartIntroTimeline.frame(at: 0.8, reduceMotion: false).scale == StartIntroTimeline.finalScale)
    }

    /// Systemet tonar startskärmen över appens första bilder i ungefär 0,3 s. Logotypen får inte röra sig då, annars syns två.
    @Test func skalanArExaktEttTillOchMed03OchAldrigOverEttDarefter() {
        for t in stride(from: 0.0, through: 0.3, by: 0.01) {
            let frame = StartIntroTimeline.frame(at: t, reduceMotion: false)
            #expect(frame == StartIntroTimeline.Frame(scale: 1, logoOpacity: 1, backgroundOpacity: 1), "t \(t)")
        }
        for t in stride(from: 0.3, through: 1.0, by: 0.01) {
            #expect(StartIntroTimeline.frame(at: t, reduceMotion: false).scale <= 1, "t \(t)")
        }
    }

    @Test func toningenSjunkerUtanAttGaUpp() {
        for reduce in [false, true] {
            let end = StartIntroTimeline.duration(reduceMotion: reduce)
            let frames = stride(from: 0.0, through: end, by: end / 40).map { StartIntroTimeline.frame(at: $0, reduceMotion: reduce) }
            #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.backgroundOpacity >= $1.backgroundOpacity }, "reduce \(reduce)")
            #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.logoOpacity >= $1.logoOpacity }, "reduce \(reduce)")
        }
    }

    @Test func reduceraRorelseGerBaraToning() {
        let end = StartIntroTimeline.duration(reduceMotion: true)
        for t in stride(from: 0.0, through: end, by: end / 20) {
            #expect(StartIntroTimeline.frame(at: t, reduceMotion: true).scale == 1)
        }
        let mid = StartIntroTimeline.frame(at: end * 0.6, reduceMotion: true)
        #expect(mid.backgroundOpacity > 0 && mid.backgroundOpacity < 1)
    }

    @Test func klartEfterLangden() {
        #expect(!StartIntroTimeline.isFinished(at: 0.79, reduceMotion: false))
        #expect(StartIntroTimeline.isFinished(at: 0.8, reduceMotion: false))
        #expect(StartIntroTimeline.isFinished(at: 0.5, reduceMotion: true))
    }

    // MARK: När introt visas

    @Test func visasVidNormalStart() {
        #expect(StartIntroTimeline.shouldPlay(voiceOverRunning: false, arguments: ["Sophamtning"], alreadyShown: false))
    }

    @Test func visasInteMedVoiceOver() {
        #expect(!StartIntroTimeline.shouldPlay(voiceOverRunning: true, arguments: [], alreadyShown: false))
    }

    @Test func visasInteMedUiTest() {
        #expect(!StartIntroTimeline.shouldPlay(voiceOverRunning: false, arguments: ["Sophamtning", "-uitest"], alreadyShown: false))
    }

    @Test func visasBaraEnGangPerProcess() {
        #expect(!StartIntroTimeline.shouldPlay(voiceOverRunning: false, arguments: [], alreadyShown: true))
    }

    @Test func ingenStartFranBorjanNarForstaBildenKommerLangeEfterProcessstarten() {
        // Processen startade i bakgrunden, till exempel för en bakgrundsuppdatering, och appen öppnas först senare.
        #expect(StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 0.5))
        #expect(StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 5))
        #expect(!StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 30))
        #expect(!StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 3600))
    }

    // MARK: Tillgångarna

    /// Startskärmens bakgrund ska vara exakt `Color.Theme.bg`, ljust och mörkt, annars syns ett hopp mellan startskärmen och introt.
    @Test func startskarmensFargArIdentiskMedTemat() throws {
        let colorset = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sophamtning/Assets.xcassets/LaunchBackground.colorset/Contents.json")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: colorset)) as? [String: Any])
        let colors = try #require(json["colors"] as? [[String: Any]])
        func hex(dark: Bool) throws -> UInt32 {
            let entry = try #require(colors.first { entry in
                let isDark = (entry["appearances"] as? [[String: String]])?.contains { $0["value"] == "dark" } ?? false
                return isDark == dark
            })
            let components = try #require((entry["color"] as? [String: Any])?["components"] as? [String: String])
            func channel(_ key: String) throws -> UInt32 {
                let text = try #require(components[key])
                return try #require(UInt32(text.dropFirst(2), radix: 16))
            }
            return try channel("red") << 16 | channel("green") << 8 | channel("blue")
        }
        #expect(try hex(dark: false) == ThemeToken.bg.light)
        #expect(try hex(dark: true) == ThemeToken.bg.dark)
    }
}
