import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SophamtningDesign

@Suite struct StartIntroTests {
    // MARK: Tidslinjen

    @Test func langdenArHogst12Sekunder() {
        #expect(StartIntroTimeline.duration(reduceMotion: false) == 1.2)
        #expect(StartIntroTimeline.duration(reduceMotion: true) <= 1.2)
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

    @Test func logotypenKrymperOchTonasUtNarDenLamnar() {
        let exit = StartIntroTimeline.exitStart(reduceMotion: false)
        #expect(StartIntroTimeline.frame(at: exit, reduceMotion: false).scale == 1)
        let mid = StartIntroTimeline.frame(at: (exit + 1.2) / 2, reduceMotion: false)
        #expect(mid.scale < 1 && mid.scale > StartIntroTimeline.finalScale)
        #expect(mid.backgroundOpacity > 0 && mid.backgroundOpacity < 1)
        #expect(StartIntroTimeline.frame(at: 1.2, reduceMotion: false).scale == StartIntroTimeline.finalScale)
        // Krympningen ska synas, inte vara ett par procent.
        #expect(StartIntroTimeline.finalScale <= 0.7)
    }

    /// Systemet tonar startskärmen över appens första bilder i ungefär 0,3 s. Logotypen får inte röra sig då, annars syns två.
    @Test func alltStarStillaTillOchMed03() {
        let still = StartIntroTimeline.Frame(scale: 1, logoOpacity: 1, backgroundOpacity: 1)
        for t in stride(from: 0.0, through: 0.3, by: 0.01) {
            #expect(StartIntroTimeline.frame(at: t, reduceMotion: false) == still, "t \(t)")
        }
    }

    @Test func ringenSnurrarEttVarvMedFartInOchUt() {
        let start = StartIntroTimeline.holdEnd, end = StartIntroTimeline.ringEnd
        #expect(start >= 0.3 && end <= 1.2)
        #expect(StartIntroTimeline.frame(at: start, reduceMotion: false).ringRotation == 0)
        #expect(StartIntroTimeline.frame(at: end, reduceMotion: false).ringRotation == 360)
        #expect(StartIntroTimeline.frame(at: 1.2, reduceMotion: false).ringRotation == 360)
        let span = end - start
        let angles = stride(from: start, through: end, by: span / 40).map { StartIntroTimeline.frame(at: $0, reduceMotion: false).ringRotation }
        #expect(zip(angles, angles.dropFirst()).allSatisfy { $0 <= $1 })
        // Fart in och ut: den första och sista tiondelen av tiden ger mycket mindre än en tiondel av varvet.
        #expect(StartIntroTimeline.frame(at: start + span / 10, reduceMotion: false).ringRotation < 18)
        #expect(StartIntroTimeline.frame(at: end - span / 10, reduceMotion: false).ringRotation > 342)
    }

    @Test func kalenderStudsarRuntEttFemtonOchLandarPaEtt() {
        let samples = stride(from: 0.0, through: 1.2, by: 0.002).map { (t: $0, scale: StartIntroTimeline.frame(at: $0, reduceMotion: false).calendarScale) }
        let peak = samples.max { $0.scale < $1.scale }!
        #expect(abs(peak.scale - 1.15) < 0.005)
        #expect(peak.t > 0.3)
        // Aldrig över 1 före 0,3 s, fjädrar under 1 på vägen ner och slutar exakt på 1.
        #expect(samples.filter { $0.t <= 0.3 }.allSatisfy { $0.scale == 1 })
        #expect(samples.contains { $0.scale < 0.97 })
        #expect(samples.last!.scale == 1)
        #expect(StartIntroTimeline.bounceStart >= 0.3)
    }

    @Test func allaStegArKlaraSenast12() {
        #expect(StartIntroTimeline.ringEnd <= 1.2)
        #expect(StartIntroTimeline.bounceEnd <= 1.2)
        #expect(StartIntroTimeline.logoFadeEnd == 1.1)
        // Logotypen får inte stå kvar ovanpå hemkortet.
        #expect(StartIntroTimeline.frame(at: 1.1, reduceMotion: false).logoOpacity == 0)
        #expect(StartIntroTimeline.frame(at: 1.0, reduceMotion: false).logoOpacity > 0)
        #expect(StartIntroTimeline.isFinished(at: 1.2, reduceMotion: false))
        #expect(!StartIntroTimeline.isFinished(at: 1.19, reduceMotion: false))
    }

    /// När hemskärmen börjar framträda går tryck igenom till den. Innan dess tar ett tryck bort introt.
    @Test func trycketFangasBaraForeUtgangen() {
        for reduce in [false, true] {
            let exit = StartIntroTimeline.exitStart(reduceMotion: reduce)
            #expect(StartIntroTimeline.capturesTouches(at: 0, reduceMotion: reduce))
            #expect(StartIntroTimeline.capturesTouches(at: exit - 0.01, reduceMotion: reduce))
            #expect(!StartIntroTimeline.capturesTouches(at: exit, reduceMotion: reduce))
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
            let frame = StartIntroTimeline.frame(at: t, reduceMotion: true)
            #expect(frame.scale == 1)
            #expect(frame.calendarScale == 1)
            #expect(frame.ringRotation == 0)
        }
        let mid = StartIntroTimeline.frame(at: end * 0.6, reduceMotion: true)
        #expect(mid.backgroundOpacity > 0 && mid.backgroundOpacity < 1)
    }

    @Test func klartEfterLangden() {
        #expect(!StartIntroTimeline.isFinished(at: 1.19, reduceMotion: false))
        #expect(StartIntroTimeline.isFinished(at: 1.2, reduceMotion: false))
        #expect(StartIntroTimeline.isFinished(at: 0.5, reduceMotion: true))
    }

    // MARK: När introt visas

    @Test func visasVidNormalStart() {
        #expect(StartIntroTimeline.shouldPlay(voiceOverRunning: false, skipsIntro: false, alreadyShown: false))
    }

    @Test func visasInteMedVoiceOver() {
        #expect(!StartIntroTimeline.shouldPlay(voiceOverRunning: true, skipsIntro: false, alreadyShown: false))
    }

    @Test func visasInteMedUiTest() {
        #expect(!StartIntroTimeline.shouldPlay(voiceOverRunning: false, skipsIntro: true, alreadyShown: false))
    }

    @Test func visasBaraEnGangPerProcess() {
        #expect(!StartIntroTimeline.shouldPlay(voiceOverRunning: false, skipsIntro: false, alreadyShown: true))
    }

    @Test func ingenStartFranBorjanNarForstaBildenKommerLangeEfterProcessstarten() {
        // Processen startade i bakgrunden, till exempel för en bakgrundsuppdatering, och appen öppnas först senare.
        #expect(StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 0.5))
        #expect(StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 5))
        #expect(!StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 30))
        #expect(!StartIntroTimeline.isFreshLaunch(secondsSinceProcessStart: 3600))
    }

    // MARK: Tillgångarna

    /// Ringen och kalendern ihop ska vara exakt `LaunchLogo`, i alla storlekar, annars syns ett hopp från startskärmen.
    @Test(arguments: ["2x", "3x"]) func lagrenIhopArPixelidentiskaMedStartskarmen(scale: String) throws {
        let assets = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sophamtning/Assets.xcassets")
        func pixels(_ name: String) throws -> (width: Int, height: Int, bytes: [UInt8]) {
            let url = assets.appendingPathComponent("\(name).imageset/\(name)@\(scale).png")
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            // Rådata utan förmultiplicering, så att även färgen i helt genomskinliga kanter jämförs som den ligger i filen.
            #expect(image.bitsPerPixel == 32 && image.bytesPerRow == image.width * 4)
            let data = try #require(image.dataProvider?.data) as Data
            return (image.width, image.height, [UInt8](data))
        }
        let logo = try pixels("LaunchLogo")
        let ring = try pixels("LaunchLogoRing")
        let calendar = try pixels("LaunchLogoCalendar")
        #expect(ring.width == logo.width && ring.height == logo.height)
        #expect(calendar.width == logo.width && calendar.height == logo.height)
        var different = 0, overlapping = 0, ringPixels = 0, calendarPixels = 0
        for offset in stride(from: 0, to: logo.bytes.count, by: 4) {
            let inRing = ring.bytes[offset + 3] > 0, inCalendar = calendar.bytes[offset + 3] > 0
            if inRing { ringPixels += 1 }
            if inCalendar { calendarPixels += 1 }
            if inRing && inCalendar { overlapping += 1 }
            // Lagren överlappar inte, så att lägga dem på varandra ger pixeln från det lager den finns i.
            let top = inCalendar ? calendar.bytes : ring.bytes
            if logo.bytes[offset + 3] > 0 || inRing || inCalendar {
                if (0..<4).contains(where: { top[offset + $0] != logo.bytes[offset + $0] }) { different += 1 }
            }
        }
        #expect(different == 0)
        #expect(overlapping == 0)
        #expect(ringPixels > calendarPixels && calendarPixels > 0)
    }

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
