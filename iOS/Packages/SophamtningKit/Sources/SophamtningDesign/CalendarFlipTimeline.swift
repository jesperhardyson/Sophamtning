import Foundation

/// Tidslinjen när kalenderbladet vänds, från ett datum till ett annat. Rena funktioner av tid, så att vyn ritar från klockan
/// och en ny vändning kan ta över mitt i en gammal. Första halvan viker det gamla bladet upp till 90 grader, och i andra halvan
/// kommer det nya fram från 90 grader. Med Reducera rörelse tonas bladet i stället ut och in, utan vridning.
public enum CalendarFlipTimeline {
    public static let half: TimeInterval = 0.18
    public static let duration: TimeInterval = 0.36

    /// Vinkel i grader runt bladets övre kant.
    public static func angle(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0, elapsed < duration else { return 0 }
        if elapsed < half {
            return -90 * CubicBezier.ease(0.42, 0, 1, 1).value(at: elapsed / half)
        }
        return 90 * (1 - CubicBezier.ease(0, 0, 0.58, 1).value(at: (elapsed - half) / half))
    }

    /// Det nya datumet visas från halva vändningen.
    public static func showsNewDate(at elapsed: TimeInterval) -> Bool {
        elapsed >= half
    }

    /// Toningen vid Reducera rörelse: bort i första halvan och in i andra.
    public static func opacity(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0, elapsed < duration else { return 1 }
        let curve = CubicBezier.easeInOut
        if elapsed < half { return 1 - curve.value(at: elapsed / half) }
        return curve.value(at: (elapsed - half) / half)
    }

    public static func isFinished(at elapsed: TimeInterval) -> Bool {
        elapsed >= duration
    }
}
