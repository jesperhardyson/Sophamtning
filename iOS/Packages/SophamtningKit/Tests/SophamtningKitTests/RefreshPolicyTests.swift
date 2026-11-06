import Testing
import Foundation
import SophamtningKit

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func at(_ seconds: TimeInterval?) -> Date? { seconds.map { base.addingTimeInterval($0) } }

/// Efter lyckad hämtning gäller 3 600 sekunder, även manuellt.
@Test(arguments: [
    // sekunder efter lyckad hämtning, manuell, tillåtet
    (0.0, false, false),
    (3599.0, false, false),
    (3600.0, false, true),
    (0.0, true, false),
    (3599.0, true, false),
    (3600.0, true, true),
])
func enGangITimmenEfterLyckadHamtning(elapsed: TimeInterval, manual: Bool, allowed: Bool) {
    let schedule = CachedSchedule(fetchedAt: at(0), lastAttemptAt: at(0))
    #expect(RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(elapsed), manual: manual) == allowed)
}

@Test func utanTidigareForsokArHamtningTillaten() {
    #expect(RefreshPolicy.canFetch(schedule: nil, now: base, manual: false))
    #expect(RefreshPolicy.canFetch(schedule: nil, now: base, manual: true))
    #expect(RefreshPolicy.canFetch(schedule: CachedSchedule(), now: base, manual: false))
}

@Test func efterMisslyckatForsokGarManuelltEfterEnMinut() {
    let schedule = CachedSchedule(fetchedAt: at(-7200), lastAttemptAt: at(0), lastError: .sourceUnavailable)
    #expect(!RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(59), manual: true))
    #expect(RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(60), manual: true))
}

@Test func efterMisslyckatForsokGarAutomatisktEfterEnTimme() {
    let schedule = CachedSchedule(fetchedAt: at(-7200), lastAttemptAt: at(0), lastError: .network)
    #expect(!RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(60), manual: false))
    #expect(!RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(3599), manual: false))
    #expect(RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(3600), manual: false))
}

@Test func misslyckatForsokUtanSvarGarAndaFortGenomManuellt() {
    let schedule = CachedSchedule(lastAttemptAt: at(0), lastError: .notFound)
    #expect(!RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(30), manual: true))
    #expect(RefreshPolicy.canFetch(schedule: schedule, now: base.addingTimeInterval(60), manual: true))
}
