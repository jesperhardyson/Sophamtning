import SophamtningKit
import SwiftUI

/// Den enda platsen som väljer färg och ikon för en fraktion.
public struct FractionStyle: Sendable {
    public let id: String
    public let name: String
    public let iconName: String
    public let foreground: Color
    public let background: Color
    /// Fraktionen har färger i temat.
    public let isKnown: Bool
    /// Färgen kommer från API:ts `color` (okänd fraktion med giltig hex).
    public let usesAPIColor: Bool

    /// Lucide-ikonerna som följer med paketet.
    static let bundledIcons: Set<String> = [
        "trash-2", "apple", "package", "cup-soda", "wine", "cylinder", "newspaper", "container", "recycle",
    ]

    private static let themed: [String: (ThemeToken, ThemeToken)] = [
        "rest": (.fracRest, .fracRestBg),
        "karl": (.fracRest, .fracRestBg),
        "mat": (.fracMat, .fracMatBg),
        "papper": (.fracPapper, .fracPapperBg),
        "tidningar": (.fracPapper, .fracPapperBg),
        "plast": (.fracPlast, .fracPlastBg),
        "glas": (.fracGlas, .fracGlasBg),
        "metall": (.fracMetall, .fracMetallBg),
    ]

    public init(id: String, info: FractionInfo) {
        self.id = id
        name = info.name
        iconName = Self.bundledIcons.contains(info.icon) ? info.icon : "recycle"
        if let (fg, bg) = Self.themed[id] {
            foreground = fg.color
            background = bg.color
            isKnown = true
            usesAPIColor = false
        } else if let rgb = parseHexColor(info.color) {
            // API:ts färg är ljus-färg. Bakgrunden är en blek ton av samma färg.
            let base = Color(rgb: rgb)
            foreground = base
            background = base.opacity(0.14)
            isKnown = false
            usesAPIColor = true
        } else {
            foreground = Color.Theme.text2
            background = Color.Theme.surface2
            isKnown = false
            usesAPIColor = false
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

/// Pillerformad märkning med ikon och namn.
public struct FractionChip: View {
    let style: FractionStyle

    public init(id: String, info: FractionInfo) {
        style = FractionStyle(id: id, info: info)
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(style.iconName, bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(style.name)
                .font(.ui(14, weight: .bold, relativeTo: .subheadline))
        }
        .foregroundStyle(style.foreground)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(style.background, in: Capsule())
        .accessibilityElement(children: .combine)
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
