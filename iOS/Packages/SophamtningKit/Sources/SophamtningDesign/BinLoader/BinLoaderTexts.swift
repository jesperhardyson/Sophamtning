import Foundation

/// Sopors roliga texter, ordagrant från `index.html`.
public enum BinLoaderTexts {
    public static let all: [String] = [
        "Slänger rester från middagen…", "Äter upp det sista i kylen först…", "Tackar av gårdagens gratäng…", "Skrapar ur stekpannan…", "Bananen hann bli för brun…",
        "Plattar till pizzakartongen…", "Trycker ner en kartong till…", "Får inte ner lådan. Provar igen…", "Tar bort tejpen från paketet…", "Viker ihop nätshoppandet…",
        "Sköljer ur yoghurtburken…", "Letar efter rätt lock…", "Är det här ens plast?", "Klämmer ihop flaskan…", "Sköljer lagom mycket…",
        "Rullar ut kärlet till vägen…", "Oj, är det redan tömning i dag?", "Springer efter sopbilen…", "Hoppas på att grannen har plats…", "Lyfter på locket försiktigt…", "Sorterar som ett proffs…",
    ]

    /// En slumpad text som aldrig är samma som `current`.
    public static func next<G: RandomNumberGenerator>(after current: String?, using generator: inout G) -> String {
        let candidates = all.filter { $0 != current }
        return candidates.randomElement(using: &generator) ?? all[0]
    }

    /// Webbens kö (`kvar`): alla texter visas i slumpad ordning innan någon upprepas. När kön är tom fylls den
    /// på igen, och första texten blir aldrig samma som den sista i förra omgången.
    public struct Queue: Sendable {
        private var remaining: [String] = []
        private var last: String?

        public init() {}

        public mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> String {
            if remaining.isEmpty { remaining = BinLoaderTexts.all }
            var index = Int.random(in: 0..<remaining.count, using: &generator)
            if remaining[index] == last, remaining.count > 1 {
                index = (index + 1) % remaining.count
            }
            let text = remaining.remove(at: index)
            last = text
            return text
        }
    }
}
