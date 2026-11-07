import SophamtningKit
import SwiftUI

/// Den enda platsen som väljer färg och ikon för en fraktion.
public struct FractionStyle: Sendable {
    public let id: String
    public let name: String
    /// Källans korta namn, "Mat", eller hela namnet när det korta saknas. För täta listor.
    public let shortName: String
    public let iconName: String
    public let foreground: Color
    public let background: Color
    /// Fraktionen har färger och ikon i temat.
    public let isKnown: Bool

    /// Lucide-ikonerna som följer med paketet.
    static let bundledIcons: Set<String> = [
        "trash-2", "apple", "package", "cup-soda", "wine", "cylinder", "newspaper", "container", "recycle",
    ]

    /// Kända fraktioner: förgrund, bakgrund och ikon bestäms av temat och designen.
    private static let themed: [String: (fg: ThemeToken, bg: ThemeToken, icon: String)] = [
        "rest": (.fracRest, .fracRestBg, "trash-2"),
        "karl": (.fracRest, .fracRestBg, "container"),
        "mat": (.fracMat, .fracMatBg, "apple"),
        "papper": (.fracPapper, .fracPapperBg, "package"),
        "tidningar": (.fracPapper, .fracPapperBg, "newspaper"),
        "plast": (.fracPlast, .fracPlastBg, "cup-soda"),
        "glas": (.fracGlas, .fracGlasBg, "wine"),
        "metall": (.fracMetall, .fracMetallBg, "cylinder"),
    ]

    /// Okända fraktioner får alltid neutral stil (text2 på surface2). API:ts färg används inte,
    /// eftersom den är en fast ljus-färg som blir oläslig i mörkt läge.
    static let unknownForeground = ThemeToken.text2
    static let unknownBackground = ThemeToken.surface2

    public init(id: String, info: FractionInfo) {
        self.id = id
        name = info.name
        let short = info.short.trimmingCharacters(in: .whitespacesAndNewlines)
        shortName = short.isEmpty ? info.name : short
        if let themed = Self.themed[id] {
            iconName = themed.icon
            foreground = themed.fg.color
            background = themed.bg.color
            isKnown = true
        } else {
            iconName = Self.bundledIcons.contains(info.icon) ? info.icon : "recycle"
            foreground = Self.unknownForeground.color
            background = Self.unknownBackground.color
            isKnown = false
        }
    }
}

/// Fraktionens ikon i en rundad ruta, 44 pt som standard. Ikonen har alltid en text för VoiceOver.
public struct FractionIconView: View {
    let style: FractionStyle
    let size: CGFloat

    public init(id: String, info: FractionInfo, size: CGFloat = 44) {
        style = FractionStyle(id: id, info: info)
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 14 / 44, style: .continuous)
            .fill(style.background)
            .frame(width: size, height: size)
            .overlay {
                Image(style.iconName, bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(style.foreground)
                    .frame(width: size * 22 / 44, height: size * 22 / 44)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(style.name)
    }
}

/// Måtten för de små chipsen i Live Activity. Två rader med tre chips ska rymmas bredvid knappen på en 375 pt bred telefon.
public enum ActivityChipMetrics {
    public static let spacing: CGFloat = 4
    static let icon: CGFloat = 12
    static let text: CGFloat = 12
}

/// Pillerformad märkning med ikon och namn. `compact` är den lilla varianten för Live Activity. Med `short` står källans
/// korta namn, som i schemaraderna, men VoiceOver läser alltid hela namnet.
public struct FractionChip: View {
    let style: FractionStyle
    let compact: Bool
    let short: Bool

    public init(id: String, info: FractionInfo, compact: Bool = false, short: Bool = false) {
        style = FractionStyle(id: id, info: info)
        self.compact = compact
        self.short = short
    }

    public var body: some View {
        HStack(spacing: compact ? 3 : 6) {
            Image(style.iconName, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: compact ? ActivityChipMetrics.icon : 16, height: compact ? ActivityChipMetrics.icon : 16)
                .accessibilityHidden(true)
            Text(short ? style.shortName : style.name)
                .font(compact ? .ui(ActivityChipMetrics.text, weight: .bold, relativeTo: .caption) : .ui(14, weight: .bold, relativeTo: .subheadline))
                .lineLimit(1)
                // Ryms ett långt namn inte på raden krymper det, i stället för att klippas, så att chipet aldrig blir
                // bredare än raden. I praktiken bara med de största textstorlekarna.
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(style.foreground)
        .padding(.leading, compact ? 5 : 8)
        .padding(.trailing, compact ? 7 : 12)
        .padding(.vertical, compact ? 3 : 6)
        .background(style.background, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.name)
    }
}

#Preview("Fraktioner") {
    let ids = ["rest", "mat", "papper", "plast", "glas", "metall", "tidningar", "karl", "tradgard"]
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ids, id: \.self) { id in
            let info = FractionInfo(name: id.capitalized, short: id, color: "#336699", icon: id == "rest" ? "trash-2" : "recycle")
            HStack { FractionIconView(id: id, info: info); FractionChip(id: id, info: info) }
        }
    }
    .padding()
    .background(Color.Theme.bg)
}

#Preview("Fraktioner mörkt") {
    HStack {
        FractionIconView(id: "glas", info: FractionInfo(name: "Glas", short: "Glas", color: "#1F6A7A", icon: "wine"))
        FractionChip(id: "plast", info: FractionInfo(name: "Plastförpackningar", short: "Plast", color: "#A8431F", icon: "cup-soda"))
    }
    .padding()
    .background(Color.Theme.bg)
    .preferredColorScheme(.dark)
}
