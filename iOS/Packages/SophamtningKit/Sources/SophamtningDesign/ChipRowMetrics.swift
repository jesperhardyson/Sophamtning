import CoreGraphics

/// Mått för en rad med chips och en text till höger, som raderna under "Kommande".
public enum ChipRowMetrics {
    /// Bredden för texten till höger ("ca om 13 d"). Texten står på en rad när det bredaste chipet ryms bredvid den.
    /// Annars bryts den till sin smalaste bredd ("ca om" och "13 d"), så att chipet får sin fulla bredd i stället för att
    /// krympa sitt namn. `available` är bredden som chipsen och texten delar, och `spacing` avståndet mellan dem.
    public static func trailingWidth(available: CGFloat, spacing: CGFloat, trailingIdeal: CGFloat, trailingMinimum: CGFloat, widestChip: CGFloat) -> CGFloat {
        if widestChip <= available - trailingIdeal - spacing { return trailingIdeal }
        return min(trailingMinimum, trailingIdeal)
    }
}
