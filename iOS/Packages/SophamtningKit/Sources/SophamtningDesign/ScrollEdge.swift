import SwiftUI

extension View {
    /// En tydlig kant under fältet, men bara när innehållet har scrollat in under det. Står innehållet överst är fältet
    /// genomskinligt och smälter in i bakgrunden, som i systemets appar. Används på en `ScrollView`.
    public func hardTopEdgeWhenScrolled() -> some View {
        modifier(HardTopEdgeWhenScrolled())
    }
}

private struct HardTopEdgeWhenScrolled: ViewModifier {
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollEdgeEffectHidden(!scrolled, for: .top)
            // Innehållet räknas som under fältet så snart det har flyttats en punkt uppåt från sitt viloläge.
            .onScrollGeometryChange(for: Bool.self, of: { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            }, action: { _, isScrolled in
                scrolled = isScrolled
            })
    }
}
