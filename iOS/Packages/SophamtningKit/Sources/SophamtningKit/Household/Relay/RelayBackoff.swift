import Foundation

/// Hur länge appen väntar innan signalerna kopplas upp igen: 1, 2, 4 och sedan högst 30 sekunder.
public enum RelayBackoff {
    /// - Parameter attempt: antalet misslyckade försök i rad, från 1.
    public static func delay(attempt: Int) -> Duration {
        .seconds(min(30, 1 << min(max(attempt, 1) - 1, 5)))
    }
}
