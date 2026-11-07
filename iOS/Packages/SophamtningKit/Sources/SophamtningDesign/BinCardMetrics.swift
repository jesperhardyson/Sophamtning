import CoreGraphics

/// Kärlkortens bredd i adressvyn. Korten är 3 av 7 kolumner, men ett långt ord i namnet ("Pappersförpackningar") gör
/// kortet bredare, högst 2/3 av bredden, så att namnet behåller samma storlek som grannkortens. Med tillgänglighetsstorlekar
/// är korten minst 4 av 5 kolumner och högst hela bredden, så att långa namn krymper mindre.
public enum BinCardMetrics {
    /// Avståndet mellan korten.
    public static let spacing: CGFloat = 12
    /// Kortets inre marginal på varje sida.
    public static let horizontalPadding: CGFloat = 14

    /// - Parameters:
    ///   - container: Bredden korten delar, utan vyns marginaler.
    ///   - content: Bredden innehållet behöver: det längsta ordet i namnet plus marginalerna.
    ///   - accessibilitySize: Sant med tillgänglighetsstorlekar.
    public static func width(container: CGFloat, content: CGFloat, accessibilitySize: Bool) -> CGFloat {
        let narrowest = accessibilitySize ? columns(4, of: 5, in: container) : columns(3, of: 7, in: container)
        let widest = accessibilitySize ? container : container * 2 / 3
        return max(narrowest, min(content, widest))
    }

    /// Bredden för `span` av `count` kolumner, som `containerRelativeFrame(count:span:spacing:)`.
    private static func columns(_ span: Int, of count: Int, in container: CGFloat) -> CGFloat {
        let column = (container - CGFloat(count - 1) * spacing) / CGFloat(count)
        return column * CGFloat(span) + CGFloat(span - 1) * spacing
    }
}
