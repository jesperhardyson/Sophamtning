#if canImport(AppKit)
import AppKit
import SophamtningDesign
import SophamtningKit
import SwiftUI
import Testing

/// Bredden för chipsen bredvid knappen **Utställt** på en 375 pt bred telefon: kortet 345 pt, marginaler 28, knappen 112 och avstånd 8.
private let availableAt375: CGFloat = 197

@Test @MainActor func sexKortaChipsRymsPaTvaRaderVid375() {
    Fonts.register()
    let shorts: [(String, String)] = [("rest", "Rest"), ("papper", "Papper"), ("plast", "Plast"), ("metall", "Metall"), ("tidningar", "Tidn."), ("glas", "Glas")]
    func width(_ part: ArraySlice<(String, String)>) -> CGFloat {
        let view = HStack(spacing: ActivityChipMetrics.spacing) {
            ForEach(Array(part), id: \.0) { id, short in
                FractionChip(id: id, info: FractionInfo(name: short, short: short, color: "#111111", icon: "trash-2"), compact: true)
            }
        }
        return NSHostingView(rootView: view).fittingSize.width
    }
    // De längsta korta namnen i samma rad är det värsta fallet.
    #expect(width(shorts[0..<3]) <= availableAt375)
    #expect(width(shorts[1..<4]) <= availableAt375)
    #expect(width(shorts[3..<6]) <= availableAt375)
}
#endif
