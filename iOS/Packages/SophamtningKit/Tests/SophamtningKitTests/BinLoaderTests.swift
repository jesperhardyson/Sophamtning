import Foundation
import Testing
@testable import SophamtningDesign

@Suite struct BinLoaderTests {
    // MARK: Tidslinjen (värden från karl-lock, karl-gung, karl-fall och karl-bak i Sopors index.html)

    @Test func lockVilarOchOppnas() {
        #expect(BinLoaderTimeline.lidAngle(at: 0) == 0)
        #expect(BinLoaderTimeline.lidAngle(at: 0.14) == 0)
        #expect(BinLoaderTimeline.lidAngle(at: 0.30) == 38)
        #expect(BinLoaderTimeline.lidAngle(at: 0.38) == 33)
        #expect(BinLoaderTimeline.lidAngle(at: 0.5) == 33)
        #expect(BinLoaderTimeline.lidAngle(at: 0.58) == 33)
        #expect(BinLoaderTimeline.lidAngle(at: 0.67) == 0)
        #expect(BinLoaderTimeline.lidAngle(at: 1) == 0)
    }

    @Test func lockOppnasMjuktMellanNyckelbilderna() {
        // Mellan 14 % och 30 % ligger vinkeln mellan 0 och 38 och stiger hela vägen.
        let steps = stride(from: 0.14, through: 0.30, by: 0.01).map { BinLoaderTimeline.lidAngle(at: $0) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
        // cubic-bezier(.2, .8, .3, 1) är snabb i början: halvvägs i tid är locket över halvvägs upp.
        #expect(BinLoaderTimeline.lidAngle(at: 0.22) > 19)
        // 30 till 38 % faller från 38 till 33 grader med ease-in-out, 34 % ligger i mitten.
        #expect(abs(BinLoaderTimeline.lidAngle(at: 0.34) - 35.5) < 0.01)
        // 58 till 67 % stänger locket med cubic-bezier(.6, 0, 1, .6), som börjar långsamt.
        #expect(BinLoaderTimeline.lidAngle(at: 0.625) > 16.5)
    }

    @Test func lockBakOchFram() {
        #expect(BinLoaderTimeline.lidIsBehindBody(at: 0) == false)
        #expect(BinLoaderTimeline.lidIsBehindBody(at: 0.159) == false)
        #expect(BinLoaderTimeline.lidIsBehindBody(at: 0.16) == true)
        #expect(BinLoaderTimeline.lidIsBehindBody(at: 0.659) == true)
        #expect(BinLoaderTimeline.lidIsBehindBody(at: 0.66) == false)
        #expect(BinLoaderTimeline.lidIsBehindBody(at: 0.99) == false)
    }

    @Test func karletGungar() {
        #expect(BinLoaderTimeline.bodySway(at: 0) == 0)
        #expect(BinLoaderTimeline.bodySway(at: 0.14) == 0)
        #expect(BinLoaderTimeline.bodySway(at: 0.30) == -3)
        #expect(BinLoaderTimeline.bodySway(at: 0.62) == -3)
        #expect(BinLoaderTimeline.bodySway(at: 0.72) == 3)
        #expect(BinLoaderTimeline.bodySway(at: 0.82) == -1.5)
        #expect(BinLoaderTimeline.bodySway(at: 0.91) == 0.5)
        #expect(BinLoaderTimeline.bodySway(at: 1) == 0)
    }

    @Test func slingaHarRattPeriod() {
        #expect(BinLoaderTimeline.period == 1.8)
        #expect(abs(BinLoaderTimeline.progress(at: 1.8 * 3 + 0.9) - 0.5) < 1e-9)
    }

    @Test func fraktionenFallerOchFaderUt() {
        let p = BinLoaderTimeline.period
        // Osynlig vid vila och precis före 9 % av 5,4 s.
        #expect(BinLoaderTimeline.fractionState(at: 0).opacity == 0)
        // Ovanför kärlet vid 11 till 13 % av 5,4 s, det vill säga 33 till 39 % av första varvet.
        let top = BinLoaderTimeline.fractionState(at: 0.36 * p)
        #expect(top.index == 0 && top.opacity == 1)
        #expect(top.x == 172 && top.y == -96 && top.rotation == -8)
        // Halvvägs i toningen (10 % av 5,4 s).
        #expect(abs(BinLoaderTimeline.fractionState(at: 0.30 * p).opacity - 0.5) < 1e-9)
        // Nere i kärlet vid 20 %, sedan borta vid 20,5 %.
        let bottom = BinLoaderTimeline.fractionState(at: 0.6 * p)
        #expect(bottom.opacity == 1 && bottom.y == 140 && bottom.rotation == 6)
        #expect(BinLoaderTimeline.fractionState(at: 0.615 * p).opacity == 0)
        #expect(BinLoaderTimeline.fractionState(at: 0.9 * p).opacity == 0)
        // Faller med cubic-bezier(.5, 0, 1, .7): långsamt i början.
        let early = BinLoaderTimeline.fractionState(at: 0.47 * p)
        #expect(early.y < -96 + (140 + 96) * 0.5)
    }

    @Test func fraktionernaVaxlarOverTreVarv() {
        let p = BinLoaderTimeline.period
        let kinds = (0..<7).map { BinLoaderTimeline.fractionState(at: (Double($0) + 0.36) * p).index }
        #expect(kinds == [0, 1, 2, 0, 1, 2, 0])
        // Varje varv ser likadant ut.
        let a = BinLoaderTimeline.fractionState(at: 0.5 * p)
        let b = BinLoaderTimeline.fractionState(at: 1.5 * p)
        #expect(abs(a.y - b.y) < 1e-9 && abs(a.opacity - b.opacity) < 1e-9 && a.index != b.index)
    }

    @Test func textenTonarInOchUt() {
        #expect(BinLoaderTimeline.textOpacity(at: 0) == 0)
        #expect(BinLoaderTimeline.textOpacity(at: 0.54) == 1)
        #expect(BinLoaderTimeline.textOpacity(at: 1.8) == 1)
        #expect(abs(BinLoaderTimeline.textOpacity(at: 3.6 - 0.54) - 1) < 1e-9)
        #expect(abs(BinLoaderTimeline.textOpacity(at: 3.6)) < 1e-9)
        #expect(BinLoaderTimeline.textPeriod == 3.6)
        #expect(BinLoaderTimeline.textCycle(at: 3.59) == 0)
        #expect(BinLoaderTimeline.textCycle(at: 3.6) == 1)
    }

    @Test func inToningenStartarEfter300ms() {
        #expect(BinLoaderTimeline.appearOpacity(at: 0) == 0)
        #expect(BinLoaderTimeline.appearOpacity(at: 0.3) == 0)
        #expect(BinLoaderTimeline.appearOpacity(at: 0.55) == 1)
        let mid = BinLoaderTimeline.appearOpacity(at: 0.425)
        #expect(mid > 0.5 && mid < 1) // ease-out
    }

    // MARK: Texterna

    @Test func texternaStammerMedWebben() {
        #expect(BinLoaderTexts.all.contains("Plattar till pizzakartongen…"))
        #expect(BinLoaderTexts.all.count == 21)
        #expect(BinLoaderTexts.all.first == "Slänger rester från middagen…")
        #expect(BinLoaderTexts.all.last == "Sorterar som ett proffs…")
    }

    @Test func textBytsAldrigTillSamma() {
        var rng = SystemRandomNumberGenerator()
        var current = BinLoaderTexts.all[0]
        for _ in 0..<100 {
            let next = BinLoaderTexts.next(after: current, using: &rng)
            #expect(next != current)
            #expect(BinLoaderTexts.all.contains(next))
            current = next
        }
    }

    @Test func koVisarAllaInnanNagonUpprepas() {
        var rng = SystemRandomNumberGenerator()
        var queue = BinLoaderTexts.Queue()
        var previous: String?
        for _ in 0..<5 {
            let round = (0..<BinLoaderTexts.all.count).map { _ in queue.next(using: &rng) }
            #expect(Set(round).count == BinLoaderTexts.all.count)
            #expect(round.first != previous)
            previous = round.last
        }
    }

    @Test func koBytsAldrigTillSammaIEnFoljd() {
        var rng = SystemRandomNumberGenerator()
        var queue = BinLoaderTexts.Queue()
        var last = queue.next(using: &rng)
        for _ in 0..<500 {
            let next = queue.next(using: &rng)
            #expect(next != last)
            last = next
        }
    }

    // MARK: SVG-banorna

    @Test func svgBanorTolkasRatt() {
        let path = SVGPathParser.parse("M10 20l5 5h-5v-10z")
        let box = path.boundingRect
        #expect(box == CGRect(x: 10, y: 15, width: 5, height: 10))
        // Implicita upprepningar och tal utan inledande nolla.
        let curve = SVGPathParser.parse("M0 0c.5.5 1-.5 2 0")
        #expect(!curve.isEmpty)
    }

    @Test func allaKarletsBanorGarAttTolka() {
        for part in BinArtwork.bodyParts + BinArtwork.lidParts {
            #expect(!part.path.isEmpty)
        }
        #expect(BinArtwork.lidParts.count == 7)
    }
}
