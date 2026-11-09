import CoreGraphics
import SophamtningDesign
import Testing

/// Bredden för "dagar kvar" till höger om chipsen på en schemarad. `available` är bredden chipsen och texten delar.
@Suite struct ChipRowWidthTests {
    private let available: CGFloat = 250
    private let spacing: CGFloat = 14

    @Test func textenFarSinBreddNarChipsenRyms() {
        // "om 6 d" bredvid ett kort chip: texten står på en rad.
        let width = ChipRowMetrics.trailingWidth(available: available, spacing: spacing, trailingIdeal: 50, trailingMinimum: 30, widestChip: 120)
        #expect(width == 50)
    }

    @Test func textenBryterNarDetBredasteChipetAnnarsKrymper() {
        // "ca om 13 d" bredvid "Pappersförpackningar": texten bryts till sin smalaste bredd, så att chipet får sin bredd.
        let width = ChipRowMetrics.trailingWidth(available: available, spacing: spacing, trailingIdeal: 80, trailingMinimum: 35, widestChip: 192)
        #expect(width == 35)
        #expect(available - width - spacing >= 192)
    }

    @Test func textenBryterAvenNarChipetInteRymsAndå() {
        // Får chipet inte plats ens då, står texten så smal som möjligt, och chipet krymper så lite som möjligt.
        let width = ChipRowMetrics.trailingWidth(available: available, spacing: spacing, trailingIdeal: 80, trailingMinimum: 35, widestChip: 240)
        #expect(width == 35)
    }

    @Test func gransenRaknasMedMellanrummet() {
        // Precis så att chipet ryms bredvid hela texten.
        let width = ChipRowMetrics.trailingWidth(available: available, spacing: spacing, trailingIdeal: 80, trailingMinimum: 35, widestChip: available - 80 - spacing)
        #expect(width == 80)
    }
}
