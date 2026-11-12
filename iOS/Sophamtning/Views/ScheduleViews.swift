import SophamtningDesign
import SophamtningKit
import SwiftUI

/// En dag i schemat: liten datumbricka, kärlen som chips och dagar kvar till höger. Avvikelse och varning står under.
/// Används under "Kommande" och i hela schemat.
struct ScheduleRowView: View {
    let row: AddressDetail.Row

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .headline) private var scaledBadgeWidth: CGFloat = 52

    /// Brickan växer med texten, men högst till 110 pt, så att raden ryms med största text.
    private var badgeWidth: CGFloat { min(scaledBadgeWidth, 110) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if typeSize.isAccessibilitySize {
                // Under varandra, så att chipsen och dagarna får hela bredden. Dagarna står bredvid brickan när de ryms,
                // annars under den.
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            badge
                            days.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            badge
                            days
                        }
                    }
                    chips
                }
            } else {
                HStack(spacing: 14) {
                    badge
                    // Chipsen och dagarna delar bredden. Dagarna bryts hellre än att ett långt namn krymper.
                    ChipRowLayout(chipSpacing: 6, spacing: 14) {
                        ForEach(row.fractions) { fraction in
                            FractionChip(id: fraction.id, info: fraction.info)
                        }
                        days
                    }
                }
            }
            // Avvikelse och varning tar hela radens bredd, så att ingen text trängs ihop.
            if let deviation = row.deviation {
                Text(deviation)
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let warning = row.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var badge: some View {
        VStack(spacing: 0) {
            Text(row.dayNumber)
                .font(.brand(22, relativeTo: .title3))
                .foregroundStyle(Color.Theme.text)
            Text(row.month)
                .font(.ui(11, weight: .heavy, relativeTo: .caption2))
                .foregroundStyle(Color.Theme.text2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 6)
        .frame(width: badgeWidth)
        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chips: some View {
        FlowLayout(spacing: 6) {
            ForEach(row.fractions) { fraction in
                FractionChip(id: fraction.id, info: fraction.info)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var days: some View {
        Text(row.shortDaysText)
            .font(.ui(15, weight: .heavy, relativeTo: .callout))
            .foregroundStyle(Color.Theme.brandText)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Chipsen flödar till vänster och den sista vyn, texten med dagar kvar, står till höger. Båda centreras vertikalt.
/// Ryms inte det bredaste chipet bredvid texten bryts texten till två rader ("ca om" och "13 d") i stället för att chipets
/// namn krymper. Bredden bestäms av `ChipRowMetrics.trailingWidth`.
struct ChipRowLayout: Layout {
    var chipSpacing: CGFloat
    var spacing: CGFloat

    private struct Arrangement {
        var size: CGSize
        var chipOrigins: [CGPoint]
        var chipsHeight: CGFloat
        var chipsWidth: CGFloat
        var trailingSize: CGSize
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let trailing = subviews.last else { return }
        let result = arrange(width: bounds.width, subviews: subviews)
        let chipsTop = bounds.minY + (bounds.height - result.chipsHeight) / 2
        for (index, origin) in result.chipOrigins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: chipsTop + origin.y), proposal: ProposedViewSize(width: result.chipsWidth, height: nil))
        }
        trailing.place(
            at: CGPoint(x: bounds.maxX - result.trailingSize.width, y: bounds.minY + (bounds.height - result.trailingSize.height) / 2),
            proposal: ProposedViewSize(width: result.trailingSize.width, height: nil)
        )
    }

    private func arrange(width proposed: CGFloat?, subviews: Subviews) -> Arrangement {
        guard let trailing = subviews.last else { return Arrangement(size: .zero, chipOrigins: [], chipsHeight: 0, chipsWidth: 0, trailingSize: .zero) }
        let chips = subviews.dropLast()
        let ideal = trailing.sizeThatFits(.unspecified)
        let trailingWidth: CGFloat
        if let proposed {
            let widestChip = chips.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            trailingWidth = ChipRowMetrics.trailingWidth(available: proposed, spacing: spacing, trailingIdeal: ideal.width, trailingMinimum: twoLineWidth(of: trailing, ideal: ideal), widestChip: widestChip)
        } else {
            trailingWidth = ideal.width
        }
        let trailingSize = trailing.sizeThatFits(ProposedViewSize(width: trailingWidth, height: nil))
        let chipsWidth = proposed.map { max($0 - trailingSize.width - spacing, 0) } ?? .infinity

        // Som `FlowLayout`: chipsen får högst områdets bredd och bryts till nästa rad när de inte ryms.
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for chip in chips {
            let size = chip.sizeThatFits(ProposedViewSize(width: chipsWidth.isFinite ? chipsWidth : nil, height: nil))
            if x > 0, x + size.width > chipsWidth {
                x = 0
                y += rowHeight + chipSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + chipSpacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - chipSpacing)
        }
        let chipsHeight = y + rowHeight
        let width = proposed ?? (maxX + spacing + trailingSize.width)
        return Arrangement(
            size: CGSize(width: width, height: max(chipsHeight, trailingSize.height)),
            chipOrigins: origins,
            chipsHeight: chipsHeight,
            chipsWidth: chipsWidth.isFinite ? chipsWidth : maxX,
            trailingSize: trailingSize
        )
    }

    /// Den smalaste bredden där texten ryms på två rader, till exempel "ca om" över "13 d".
    private func twoLineWidth(of trailing: LayoutSubview, ideal: CGSize) -> CGFloat {
        let twoLines = ideal.height * 2 + 1
        var low: CGFloat = 0, high = ideal.width
        for _ in 0..<12 {
            let mid = (low + high) / 2
            if trailing.sizeThatFits(ProposedViewSize(width: mid, height: nil)).height <= twoLines { high = mid } else { low = mid }
        }
        return ceil(high)
    }
}

/// Raderna i en vit ruta. Avgränsaren följer sin rad, så att den aldrig syns i en tom ruta.
struct ScheduleList: View {
    let rows: [AddressDetail.Row]
    /// Om raderna ska synas. `nil` låter varje rad komma in när den visas första gången.
    var shown: Bool?

    var body: some View {
        ResultList {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let item = VStack(spacing: 0) {
                    if index > 0 { ResultDivider() }
                    ScheduleRowView(row: row)
                }
                if let shown {
                    item.rowEntrance(shown: shown, index: index)
                } else {
                    item.rowEntranceOnAppear(index: index)
                }
            }
        }
    }
}

/// En rad per kärl under "Per kärl": chipset till vänster, och datum och dagar kvar till höger. Läses som ett element
/// av VoiceOver, med hela namnet. Med tillgänglighetsstorlekar står datumet under chipset.
struct BinRow: View {
    let bin: AddressDetail.Bin

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    chip
                    when(alignment: .leading)
                }
            } else {
                // Som raderna under Kommande: ryms inte chipet bredvid datumet bryts datumet, i stället för att namnet krymper.
                ChipRowLayout(chipSpacing: 6, spacing: 14) {
                    chip
                    when(alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bin.accessibilityLabel)
    }

    private var chip: some View {
        FractionChip(id: bin.id, info: bin.info)
    }

    private func when(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(bin.dateText)
                .font(.ui(15, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(Color.Theme.text)
            Text(bin.daysText)
                .font(.ui(14, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.Theme.text2)
        }
        .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
    }
}

/// Hela det kommande schemat, i samma format som raderna under "Kommande". Saknas schemat visas samma meddelanden som i
/// adressvyn, och försvinner adressen medan vyn är öppen står det varför. Vyn är aldrig tom.
struct FullScheduleView: View {
    let model: AppModel
    let key: AddressKey
    let onSearchAgain: () -> Void

    @State private var sources: [Source]?
    @State private var link: WebLink?

    var body: some View {
        ZStack {
            Color.Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let address = model.addresses.first(where: { $0.key == key }) {
                        content(for: address)
                    } else {
                        missingAddress
                    }
                }
                // Samma kant som den stora rubriken i fältet, och raderna direkt under rubriken som i adressvyn.
                .padding(.horizontal, PageMargin.horizontal)
                .padding(.bottom, 32)
            }
            .refreshable { await model.refreshAll(manual: true) }
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
        .navigationTitle("Hela schemat")
        .navigationBarTitleDisplayMode(.large)
        .task { sources = await model.sourceList() }
        .inAppBrowser(item: $link)
    }

    @ViewBuilder
    private func content(for address: SavedAddress) -> some View {
        let detail = AddressDetail.make(
            address: address,
            schedule: model.schedule(for: key),
            settings: model.settings,
            sourceName: sources.map { sourceName(key.source, in: $0) },
            now: model.currentDate,
            household: model.household,
            ownPlacedOut: model.ownPlacedOut,
            silencedPickups: model.householdSilencedPickups
        )
        // Rubriken är "Hela schemat", så namnet står här, och gatan när den skiljer sig från namnet.
        AddressLinesView(lines: detail.namedLines, size: 18, addressStyle: .body)
            .padding(.bottom, AddressLinesView.bottomSpacing)
        AddressNoticeView(model: model, notice: detail.notice, onSearchAgain: { onSearchAgain() })
        if let note = detail.otherDays {
            OtherDaysCard(note: note)
                .padding(.bottom, 12)
        }
        switch detail.mode {
        case .loading:
            ScheduleLoadingCard()
        case .unavailable:
            // Felet står i meddelandet ovan.
            EmptyView()
        case .noUpcoming:
            NoUpcomingCard(message: detail.noUpcomingMessage)
        case .schedule:
            ScheduleList(rows: detail.rows)
        }
        if let period = detail.schedulePeriod {
            SchedulePeriodView(line: period)
                .padding(.top, 12)
        }
        SourceCard(source: key.source, sources: sources, detail: detail, webLink: $link)
            .padding(.top, 28)
    }

    /// Adressen togs bort, eller adresserna går inte att läsa just nu. Ett läsfel får aldrig se ut som en borttagen adress.
    @ViewBuilder
    private var missingAddress: some View {
        if model.storageProblem == .addressesUnreadable || model.storageProblem == .addressesUnavailable {
            MessageCard(style: .warning, icon: "externaldrive.badge.xmark", title: "Dina adresser kan inte läsas just nu", message: "Inget har raderats. Gå tillbaka till hemskärmen och försök igen.")
        } else {
            MessageCard(style: .neutral, icon: "mappin.slash", title: "Adressen är borttagen", message: "Den finns inte längre bland dina sparade adresser.")
        }
    }
}

/// Rutan för ett område där vissa gator har en annan hämtdag, med samma utseende som den neutrala `MessageCard`. Rubriken
/// läses som rubrik och raderna efter den. Står överst, före datumen, så att den som bor på en sådan gata ser den först.
struct OtherDaysCard: View {
    let note: OtherDaysNote
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.Theme.text)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.heading)
                    .font(.ui(15, weight: .heavy, relativeTo: .subheadline))
                    .foregroundStyle(Color.Theme.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(note.rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(.ui(14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.Theme.text2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("otherDaysCard")
    }
}

/// Meddelandet högst upp i adressvyn och i hela schemat när hämtningen eller sparandet har misslyckats.
struct AddressNoticeView: View {
    let model: AppModel
    let notice: AddressDetail.Notice?
    /// Öppnar sökningen igen, för en adress som källan inte längre känner igen.
    let onSearchAgain: () -> Void

    var body: some View {
        switch notice {
        case .savedShown(let fetched):
            MessageCard(
                style: .neutral,
                icon: "icloud.slash",
                title: "Visar senast hämtade schema",
                message: ["Källan svarar inte just nu.", fetched].compactMap { $0 }.joined(separator: " ")
            )
            .padding(.bottom, 20)
        case .sourceUnavailable:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "icloud.slash", title: "Källan svarar inte just nu", message: "Schemat kan inte hämtas. Det betyder inte att adressen saknas.")
                Button { Task { await model.refreshAll(manual: true) } } label: { PrimaryButtonLabel(title: "Försök igen") }
                    .buttonStyle(.pressable)
            }
            .padding(.bottom, 20)
        case .notFound:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "location.slash", title: "Adressen hittas inte längre", message: "Källan känner inte igen adressen. Sök upp den på nytt för att få schemat.")
                Button { onSearchAgain() } label: { PrimaryButtonLabel(title: "Sök igen") }
                    .buttonStyle(.pressable)
            }
            .padding(.bottom, 20)
        case .badRequest:
            // Samma anrop upprepas inte, så det finns ingen Försök igen.
            MessageCard(
                style: .warning,
                icon: "exclamationmark.triangle",
                title: "Källan godtog inte förfrågan",
                message: "Förfrågan för den här adressen avvisades. Det betyder inte att adressen saknas. Appen hämtar schemat på nytt som vanligt, högst en gång i timmen."
            )
            .padding(.bottom, 20)
        case .storageFailed:
            VStack(spacing: 12) {
                MessageCard(style: .warning, icon: "externaldrive.badge.xmark", title: "Schemat kunde inte sparas", message: "Det går inte att spara på telefonen just nu, och schemat visas först när det har sparats. Det betyder inte att adressen saknas.")
                Button { Task { await model.refreshAll(manual: true) } } label: { PrimaryButtonLabel(title: "Försök igen") }
                    .buttonStyle(.pressable)
            }
            .padding(.bottom, 20)
        case nil:
            EmptyView()
        }
    }
}

/// Schemat hämtas för första gången.
struct ScheduleLoadingCard: View {
    var body: some View {
        BinLoaderView(textColor: Color.Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Schemat finns men har inga hämtningar från och med i dag. Har källans period passerat står det att nästa period
/// inte är publicerad än, med källans orsak.
struct NoUpcomingCard: View {
    let message: AddressDetail.NoUpcomingMessage

    var body: some View {
        MessageCard(style: .neutral, icon: "calendar.badge.exclamationmark", title: message.title, message: message.message)
    }
}

/// "Schemat gäller till 10 januari 2027." och källans orsak i mindre text under.
struct SchedulePeriodView: View {
    let line: AddressDetail.SchedulePeriodLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(Color.Theme.text2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.text)
                    .font(.ui(16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(Color.Theme.text)
                if let reason = line.reason {
                    Text(reason)
                        .font(.ui(14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.Theme.text2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
