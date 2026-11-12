import Foundation

/// Pratbubblorna som syns just nu. Varje tryck lägger till en, och var och en syns sin egen tid
/// (`BinBubbleTimeline.duration`) räknat från sitt eget tryck. Högst `maxCount` åt gången, så att snabba tryck inte
/// täcker skärmen: blir de fler får den äldsta lämna plats.
public struct BinBubbleStack: Equatable, Sendable {
    public struct Bubble: Identifiable, Equatable, Sendable {
        public let id: Int
        public let text: String
        public let start: Date
    }

    /// Flest bubblor samtidigt.
    public static let maxCount = 3

    /// Äldst först, så att den nyaste står närmast kärlet.
    public private(set) var bubbles: [Bubble] = []
    private var nextID = 0

    public init() {}

    /// Lägger till en bubbla. Bubblor som redan visats klart tas bort, och den äldsta lämnar plats om de blir för många.
    public mutating func add(_ text: String, at date: Date) {
        removeExpired(at: date)
        bubbles.append(Bubble(id: nextID, text: text, start: date))
        nextID += 1
        if bubbles.count > Self.maxCount { bubbles.removeFirst(bubbles.count - Self.maxCount) }
    }

    /// Tar bort bubblorna som har visats klart.
    public mutating func removeExpired(at date: Date) {
        bubbles.removeAll { !BinBubbleTimeline.isShowing(elapsed: date.timeIntervalSince($0.start)) }
    }

    /// När nästa bubbla har tonats bort, eller `nil` om ingen syns. Den äldsta försvinner först.
    public var nextExpiry: Date? {
        bubbles.first.map { $0.start.addingTimeInterval(BinBubbleTimeline.duration) }
    }
}
