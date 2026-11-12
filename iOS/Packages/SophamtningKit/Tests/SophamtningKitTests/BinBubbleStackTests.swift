import Foundation
import Testing
@testable import SophamtningDesign

/// Flera pratbubblor samtidigt: varje tryck lägger till en, och var och en syns sin egen tid.
@Suite struct BinBubbleStackTests {
    let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func varjeTryckLaggerTillEnBubbla() {
        var stack = BinBubbleStack()
        stack.add("Ett", at: start)
        stack.add("Två", at: start.addingTimeInterval(0.3))
        // Äldst först, så att den nyaste står närmast kärlet.
        #expect(stack.bubbles.map(\.text) == ["Ett", "Två"])
        #expect(Set(stack.bubbles.map(\.id)).count == 2)
    }

    @Test func varjeBubblaSynsSinEgenTid() {
        var stack = BinBubbleStack()
        stack.add("Ett", at: start)
        stack.add("Två", at: start.addingTimeInterval(1))
        // Den första har visats klart, den andra syns kvar.
        stack.removeExpired(at: start.addingTimeInterval(BinBubbleTimeline.duration))
        #expect(stack.bubbles.map(\.text) == ["Två"])
        stack.removeExpired(at: start.addingTimeInterval(1 + BinBubbleTimeline.duration))
        #expect(stack.bubbles.isEmpty)
    }

    @Test func nastaBubblaSomTonasBortStyrKlockan() {
        var stack = BinBubbleStack()
        #expect(stack.nextExpiry == nil)
        stack.add("Ett", at: start)
        stack.add("Två", at: start.addingTimeInterval(0.5))
        #expect(stack.nextExpiry == start.addingTimeInterval(BinBubbleTimeline.duration))
    }

    @Test func hogstTreBubblorSamtidigt() {
        var stack = BinBubbleStack()
        for (index, text) in ["Ett", "Två", "Tre", "Fyra"].enumerated() {
            stack.add(text, at: start.addingTimeInterval(Double(index) * 0.1))
        }
        // Den äldsta får lämna plats.
        #expect(BinBubbleStack.maxCount == 3)
        #expect(stack.bubbles.map(\.text) == ["Två", "Tre", "Fyra"])
    }

    @Test func enUtgangenBubblaForsvinnerNarEnNyLaggsTill() {
        var stack = BinBubbleStack()
        stack.add("Ett", at: start)
        stack.add("Två", at: start.addingTimeInterval(5))
        #expect(stack.bubbles.map(\.text) == ["Två"])
    }
}
