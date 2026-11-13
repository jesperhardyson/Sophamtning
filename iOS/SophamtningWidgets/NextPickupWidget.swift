import SophamtningDesign
import SophamtningKit
import SwiftUI
import WidgetKit

// MARK: Tidslinje

struct NextPickupEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
    /// Fraktionernas namn och ikoner ur det sparade schemat.
    let fractionInfo: [String: FractionInfo]
    /// "Schemat slutar 10 jan" när schemat tar slut inom 14 dagar.
    var scheduleEnding: ScheduleEnding?
    /// Någon i hushållet har ställt ut kärlen för nästa tömning.
    var placedOut = false
    /// "av Sofie" eller "av dig", när det är känt vem som ställde ut.
    var placedOutBy: String?
    /// Tömningen som knappen Ställ ut kärlen markerar, när den visas: i dag eller i morgon och inte utställd.
    var placeOut: PlacedOut?

    /// Texterna på låsskärmen.
    var lockScreen: LockScreenContent {
        LockScreenContent.make(content: content, info: fractionInfo, placedOut: placedOut)
    }

    func info(for id: String) -> FractionInfo {
        ScheduleLogic.displayInfo(for: id, in: fractionInfo)
    }
}

/// Läser bara från lagringen. Inga nätanrop och inga skrivningar: appen och bakgrundsuppdateringen hämtar och sparar.
struct NextPickupProvider: TimelineProvider {
    /// Tidslinjen innehåller en post per svensk midnatt så här många dagar framåt.
    private static let days = 7

    private let store = LocalStore.shared()

    func placeholder(in context: Context) -> NextPickupEntry {
        .sample
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextPickupEntry) -> Void) {
        // Widgetgalleriet visar exempeldata, aldrig användarens adress.
        completion(context.isPreview ? .sample : entries(now: Date()).first ?? .sample)
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextPickupEntry>) -> Void) {
        let now = Date()
        let data = WidgetData.read(from: store)
        let list = entries(data: data, now: now)
        // Går filerna inte att läsa försöker widgeten igen inom 15 minuter. Annars byter den dag vid svensk midnatt,
        // och appen laddar om den när något sparas.
        let policy: TimelineReloadPolicy = data.reloadDate(after: now).map { .after($0) } ?? .atEnd
        completion(Timeline(entries: list, policy: policy))
    }

    private func entries(now: Date) -> [NextPickupEntry] {
        entries(data: WidgetData.read(from: store), now: now)
    }

    private func entries(data: WidgetData, now: Date) -> [NextPickupEntry] {
        if data.reloadDate(after: now) != nil {
            return [NextPickupEntry(date: now, content: data.content(at: now), fractionInfo: data.fractionInfo, scheduleEnding: data.scheduleEnding(at: now), placedOut: data.placedOut(at: now), placedOutBy: data.placedOutBy(at: now), placeOut: data.placeOutEntry(at: now))]
        }
        return WidgetContent.timelineDates(from: now, days: Self.days).map {
            NextPickupEntry(date: $0, content: data.content(at: $0), fractionInfo: data.fractionInfo, scheduleEnding: data.scheduleEnding(at: $0), placedOut: data.placedOut(at: $0), placedOutBy: data.placedOutBy(at: $0), placeOut: data.placeOutEntry(at: $0))
        }
    }
}

// MARK: Widget

struct NextPickupWidget: Widget {
    static let kind = "se.hardyson.sophamtning.nextpickup"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NextPickupProvider()) { entry in
            NextPickupView(entry: entry)
                // Utan `widgetURL` öppnar ett tryck på widgeten appen.
                .containerBackground(Color.Theme.surface, for: .widget)
        }
        .configurationDisplayName("Nästa tömning")
        .description("Visar när soporna hämtas härnäst på din huvudadress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: Vyer

struct NextPickupView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextPickupEntry

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular:
            LockScreenWidget(family: family, content: entry.lockScreen)
        default:
            homeScreen
        }
    }

    @ViewBuilder private var homeScreen: some View {
        switch entry.content {
        case .pickup(let name, let relative, let shortDate, let fractions):
            if family == .systemMedium {
                MediumPickup(entry: entry, name: name, relative: relative, fractions: fractions)
            } else {
                SmallPickup(entry: entry, name: name, relative: relative, shortDate: shortDate, fractions: fractions)
            }
        case .noAddress:
            WidgetMessage(symbol: "mappin.and.ellipse", title: "Lägg till en adress i appen", detail: nil)
        case .unavailable:
            // Filerna går inte att läsa just nu, till exempel före första upplåsningen. Adressen är inte borta.
            WidgetMessage(symbol: "lock", title: "Kan inte visa schemat just nu", detail: "Widgeten uppdateras igen om en stund.")
        case .noSchedule(let name):
            WidgetMessage(symbol: "arrow.triangle.2.circlepath", title: "Schemat har inte hämtats än", detail: "Öppna appen för att hämta det.", name: name)
        case .failed(let name):
            WidgetMessage(symbol: "exclamationmark.triangle", title: "Kunde inte hämta schemat", detail: "Öppna appen och försök igen.", name: name)
        case .notFound(let name):
            WidgetMessage(symbol: "questionmark.circle", title: "Adressen hittas inte längre", detail: "Öppna appen för att söka igen.", name: name)
        case .noUpcoming(let name):
            WidgetMessage(symbol: "calendar", title: "Inga kommande hämtningar", detail: nil, name: name)
        }
    }
}

/// Versal först, som "Om 3 dagar" i designen.
private func capitalized(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}

/// Fraktionerna som hämtas första datumet.
private func firstDay(_ fractions: [FractionPickup]) -> [FractionPickup] {
    guard let first = fractions.first else { return [] }
    return fractions.filter { $0.date == first.date }
}

/// Allt widgeten visar som en mening, för VoiceOver. Alla fraktioner med namn, också de som bara syns som ikoner.
/// "Schemat slutar …" ingår också när `ViewThatFits` har utelämnat raden för att den inte ryms: det är avsiktligt, eftersom
/// informationen är viktig och VoiceOver inte har någon platsbrist.
private func spokenSummary(name: String, relative: String, shortDate: String, fractions: [FractionPickup], entry: NextPickupEntry) -> String {
    let today = firstDay(fractions).map { entry.info(for: $0.fraction).name }.joined(separator: ", ")
    let later = fractions.dropFirst(firstDay(fractions).count).map {
        "\(entry.info(for: $0.fraction).name) \(WidgetContent.rowDate($0))"
    }
    return ([name, "\(capitalized(relative)), \(shortDate)", today] + (entry.placedOut ? [[HouseholdTexts.widgetPlacedOut, entry.placedOutBy].compactMap { $0 }.joined(separator: " ")] : []) + (later.isEmpty ? [] : ["Senare: " + later.joined(separator: ", ")]) + [entry.scheduleEnding?.spokenText].compactMap { $0 })
        .joined(separator: ". ")
}

/// Liten: bara plats för ikoner i designen. Namnen finns för VoiceOver, och en ensam fraktion visas också med sitt namn.
private struct SmallPickup: View {
    let entry: NextPickupEntry
    let name: String
    let relative: String
    let shortDate: String
    let fractions: [FractionPickup]

    var body: some View {
        // Raden om att schemat slutar står längst ned, men bara när den ryms. Annars utelämnas den hellre än att något
        // annat klipps.
        // "Utställt" går före raden om schemat.
        ViewThatFits(in: .vertical) {
            content(showsEnding: entry.scheduleEnding != nil, showsPlacedOut: entry.placedOut)
            content(showsEnding: false, showsPlacedOut: entry.placedOut)
            content(showsEnding: false, showsPlacedOut: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(name: name, relative: relative, shortDate: shortDate, fractions: fractions, entry: entry))
    }

    private func content(showsEnding: Bool, showsPlacedOut: Bool) -> some View {
        let shown = firstDay(fractions)
        return VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.ui(14, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text2)
                .lineLimit(1)
            Text(capitalized(relative))
                .font(.brand(28, relativeTo: .title))
                .foregroundStyle(Color.Theme.text)
                .lineLimit(1)
                // "Ca i övermorgon" är den längsta formen, cirka 7 procent bredare än "Ca om 12 dagar".
                .minimumScaleFactor(0.5)
            Text(shortDate)
                .font(.ui(16, weight: .bold, relativeTo: .callout))
                .foregroundStyle(Color.Theme.brandText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            icons(shown)
            if showsPlacedOut {
                PlacedOutLine(size: 13, by: entry.placedOutBy)
                    .padding(.top, 6)
            }
            if showsEnding, let ending = entry.scheduleEnding {
                EndingLine(text: ending.shortText, size: 12)
                    .padding(.top, 6)
            }
        }
    }

    private func name(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.ui(14, weight: .heavy, relativeTo: .subheadline))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func icons(_ shown: [FractionPickup]) -> some View {
        if shown.count == 1, let only = shown.first {
            // Det går att visa namnet bredvid en ensam ikon.
            let info = entry.info(for: only.fraction)
            HStack(spacing: 8) {
                FractionIconView(id: only.fraction, info: info, size: 40)
                // Det fulla namnet om det ryms på en rad, annars det korta. VoiceOver läser alltid det fulla.
                ViewThatFits(in: .horizontal) {
                    name(info.name, color: FractionStyle(id: only.fraction, info: info).foreground)
                    name(info.short, color: FractionStyle(id: only.fraction, info: info).foreground)
                }
            }
        } else {
            let visible = shown.count > 3 ? Array(shown.prefix(2)) : shown
            HStack(spacing: 6) {
                ForEach(visible, id: \.fraction) { pickup in
                    FractionIconView(id: pickup.fraction, info: entry.info(for: pickup.fraction), size: 38)
                }
                if shown.count > visible.count {
                    Text("+\(shown.count - visible.count)")
                        .font(.ui(14, weight: .heavy, relativeTo: .subheadline))
                        .foregroundStyle(Color.Theme.text2)
                        .frame(width: 38, height: 38)
                        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

/// Mellan: kalenderbricka till vänster, och en rad per fraktion med datum till höger.
private struct MediumPickup: View {
    let entry: NextPickupEntry
    let name: String
    let relative: String
    let fractions: [FractionPickup]

    private static let maxRows = 3

    var body: some View {
        // Raden om att schemat slutar står under fraktionerna, men bara när den ryms. Annars utelämnas den hellre än att
        // något annat klipps.
        // "Utställt" går före raden om schemat.
        ViewThatFits(in: .vertical) {
            content(showsEnding: entry.scheduleEnding != nil, showsPlacedOut: entry.placedOut)
            content(showsEnding: false, showsPlacedOut: entry.placedOut)
            content(showsEnding: false, showsPlacedOut: false)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(name: name, relative: relative, shortDate: fractions.first.map { SwedishFormat.shortDate($0.date) } ?? "", fractions: fractions, entry: entry))
    }

    private func content(showsEnding: Bool, showsPlacedOut: Bool) -> some View {
        // Knappen tar den sista radens plats.
        let (rows, hidden) = WidgetContent.mediumRows(fractions, maxRows: entry.placeOut == nil ? Self.maxRows : Self.maxRows - 1)
        return HStack(alignment: .center, spacing: 16) {
            if let first = fractions.first {
                VStack(spacing: 4) {
                    CalendarTile(date: first.date)
                    Text(name)
                        .font(.ui(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(Color.Theme.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 78)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(capitalized(relative))
                    .font(.brand(24, relativeTo: .title2))
                    .foregroundStyle(Color.Theme.text)
                    .lineLimit(1)
                    // "Ca i övermorgon" är den längsta formen, cirka 7 procent bredare än "Ca om 12 dagar".
                    .minimumScaleFactor(0.5)
                ForEach(rows, id: \.fraction) { pickup in
                    row(pickup)
                }
                if let target = entry.placeOut {
                    // Ett tryck markerar tömningen utan att öppna appen, som Klart i Live Activityn.
                    Button(intent: MarkPlacedOutIntent(key: target.key, pickupDate: target.date)) {
                        Label("Ställ ut kärlen", systemImage: "checkmark.circle")
                            .font(.ui(14, weight: .heavy, relativeTo: .caption))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.Theme.primary)
                }
                if hidden > 0 {
                    Text("+\(hidden) till")
                        .font(.ui(13, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(Color.Theme.text2)
                }
                if showsPlacedOut {
                    PlacedOutLine(size: 13, by: entry.placedOutBy)
                }
                if showsEnding, let ending = entry.scheduleEnding {
                    EndingLine(text: ending.shortText, size: 13)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ pickup: FractionPickup) -> some View {
        let info = entry.info(for: pickup.fraction)
        return HStack(spacing: 8) {
            FractionIconView(id: pickup.fraction, info: info, size: 28)
            Text(info.name)
                .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Datumet står redan på kalenderbladet, eftersom alla rader gäller samma tömning.
            Spacer(minLength: 0)
        }
    }
}

/// "Schemat slutar 10 jan": en rad med liten ikon. Raden kortas hellre än att brytas.
private struct EndingLine: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Label {
            Text(text)
                .font(.ui(size, weight: .bold, relativeTo: .caption))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } icon: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: size, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.Theme.text2)
    }
}

/// En fylld bock och "Utställda av Sofie", när någon i hushållet har ställt ut kärlen för nästa tömning. Raden är en rad
/// hög, så att den inte tränger undan fraktionerna. Ryms inte namnet står bara "Utställda".
private struct PlacedOutLine: View {
    let size: CGFloat
    let by: String?

    var body: some View {
        Label {
            ViewThatFits(in: .horizontal) {
                if let by {
                    (Text(HouseholdTexts.widgetPlacedOut).font(.ui(size, weight: .heavy, relativeTo: .caption))
                        + Text(" " + by).font(.ui(size, weight: .semibold, relativeTo: .caption)))
                        .lineLimit(1)
                }
                Text(HouseholdTexts.widgetPlacedOut)
                    .font(.ui(size, weight: .heavy, relativeTo: .caption))
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.Theme.brandText)
    }
}

/// Lägena utan kommande hämtning: tomt, ingen adress, tekniskt fel och så vidare. Ett eget läge ser aldrig ut som ett annat.
private struct WidgetMessage: View {
    let symbol: String
    let title: String
    let detail: String?
    var name: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.Theme.primary)
                .accessibilityHidden(true)
            if let name {
                Text(name)
                    .font(.ui(13, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(Color.Theme.text2)
                    .lineLimit(1)
            }
            Text(title)
                .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.ui(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.Theme.text2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Exempeldata och förhandsvisning

extension NextPickupEntry {
    static let infoByFraction: [String: FractionInfo] = [
        "rest": FractionInfo(name: "Restavfall", short: "Rest", color: "#474C48", icon: "trash-2"),
        "mat": FractionInfo(name: "Matavfall", short: "Mat", color: "#7A4A1E", icon: "apple"),
        "papper": FractionInfo(name: "Papper", short: "Papper", color: "#2E5E86", icon: "package"),
        "plast": FractionInfo(name: "Plastförpackningar", short: "Plast", color: "#A8431F", icon: "cup-soda"),
        "glas": FractionInfo(name: "Glas", short: "Glas", color: "#1F6A7A", icon: "wine"),
        "metall": FractionInfo(name: "Metall", short: "Metall", color: "#6B4F7A", icon: "cylinder"),
    ]

    private static func pickup(_ id: String, _ iso: String, days: Int, estimated: Bool = false) -> FractionPickup {
        FractionPickup(fraction: id, date: DayDate(iso)!, estimated: estimated, warning: nil, daysUntil: days)
    }

    private static func entry(_ content: WidgetContent) -> NextPickupEntry {
        NextPickupEntry(date: Date(), content: content, fractionInfo: infoByFraction)
    }

    /// Designens exempel: tre dagar kvar, två fraktioner på måndag och papper senare.
    static let sample = entry(.pickup(name: "Hemma", relative: "om 3 dagar", shortDate: "Mån 9 nov", fractions: [
        pickup("rest", "2026-11-09", days: 3), pickup("mat", "2026-11-09", days: 3), pickup("papper", "2026-11-12", days: 6, estimated: true),
    ]))

    /// Alla lägen, till förhandsvisningarna.
    static let previews: [(String, NextPickupEntry)] = [
        ("Nästa tömning", sample),
        ("Utställt", NextPickupEntry(date: Date(), content: sample.content, fractionInfo: infoByFraction, placedOut: true, placedOutBy: "av Sofie")),
        ("Ensam fraktion", entry(.pickup(name: "Hemma", relative: "i morgon", shortDate: "Sön 8 nov", fractions: [pickup("plast", "2026-11-08", days: 1)]))),
        ("Beräknat datum", entry(.pickup(name: "Stugan", relative: "ca om 12 dagar", shortDate: "ca ons 18 nov", fractions: [
            pickup("rest", "2026-11-18", days: 12, estimated: true), pickup("mat", "2026-11-18", days: 12, estimated: true),
            pickup("glas", "2026-11-18", days: 12, estimated: true), pickup("metall", "2026-11-18", days: 12, estimated: true),
            pickup("papper", "2026-11-20", days: 14, estimated: true),
        ]))),
        ("Ingen adress", entry(.noAddress)),
        ("Kan inte läsas", entry(.unavailable)),
        ("Inget schema", entry(.noSchedule(name: "Hemma"))),
        ("Misslyckad hämtning", entry(.failed(name: "Hemma"))),
        ("Hittas inte (404)", entry(.notFound(name: "Hemma"))),
        ("Inga kommande", entry(.noUpcoming(name: "Hemma"))),
    ]
}

#Preview("Liten", as: .systemSmall) {
    NextPickupWidget()
} timeline: {
    for (_, entry) in NextPickupEntry.previews { entry }
}

#Preview("Mellan", as: .systemMedium) {
    NextPickupWidget()
} timeline: {
    for (_, entry) in NextPickupEntry.previews { entry }
}
