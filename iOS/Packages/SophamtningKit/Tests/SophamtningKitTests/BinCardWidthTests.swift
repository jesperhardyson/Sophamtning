import CoreGraphics
import SophamtningDesign
import Testing

/// Kärlkortens bredd i adressvyn. `container` är bredden korten delar, utan marginalerna.
@Suite struct BinCardWidthTests {
    private let container: CGFloat = 345

    @Test func kortaNamnFarTreSjundedelar() {
        // Samma bredd som förut: 3 av 7 kolumner med 12 pt mellan.
        let narrow = (container - 6 * 12) / 7 * 3 + 2 * 12
        #expect(BinCardMetrics.width(container: container, content: 80, accessibilitySize: false) == narrow)
        #expect(BinCardMetrics.width(container: container, content: 0, accessibilitySize: false) == narrow)
    }

    @Test func langtNamnGerBredareKort() {
        let width = BinCardMetrics.width(container: container, content: 200, accessibilitySize: false)
        #expect(width == 200)
    }

    @Test func aldrigBredareAnTvaTredjedelar() {
        let width = BinCardMetrics.width(container: container, content: 400, accessibilitySize: false)
        #expect(width == container * 2 / 3)
    }

    @Test func storstaTextBehallerFyraFemtedelar() {
        // Med tillgänglighetsstorlekar är korten redan 4 av 5 kolumner, bredare än 2/3, och blir aldrig smalare.
        let wide = (container - 4 * 12) / 5 * 4 + 3 * 12
        #expect(BinCardMetrics.width(container: container, content: 100, accessibilitySize: true) == wide)
        #expect(BinCardMetrics.width(container: container, content: 400, accessibilitySize: true) == wide)
    }
}

#if canImport(AppKit)
import AppKit
import SwiftUI

/// "Pappersförpackningar" ryms i full storlek på den minsta telefonen (375 pt, 327 pt för korten), med kortets marginaler.
@Test @MainActor func pappersforpackningarRymsIFullStorlek() {
    Fonts.register()
    let word = NSHostingView(rootView: Text("Pappersförpackningar").font(.ui(17, weight: .heavy, relativeTo: .headline)).fixedSize()).fittingSize.width
    let needed = word + BinCardMetrics.horizontalPadding * 2
    #expect(BinCardMetrics.width(container: 327, content: needed, accessibilitySize: false) >= needed)
}
#endif
