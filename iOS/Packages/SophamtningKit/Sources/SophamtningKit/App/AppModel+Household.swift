import Foundation

/// Hushållet i appens modell: delade adresser, bockar för Utställt och valen för notiser.
///
/// Andras bockar skrivs aldrig i `placed-out.json`, som bara är mina egna tryck. De läggs till i minnet när påminnelserna
/// planeras (`householdSilenced`), så att Ångra eller att valet stängs av ger tillbaka påminnelsen.
extension AppModel {
    // MARK: Lyssna

    /// Börjar lyssna på hushållets lägen. Anropas en gång från appen, och fler anrop gör inget.
    public func startHousehold() {
        guard householdTask == nil else { return }
        let stream = householdSync.states()
        householdTask = Task { [weak self] in
            for await state in stream {
                guard let self else { return }
                await self.receiveHousehold(state)
            }
        }
    }

    /// Hämtar hushållets ändringar nu, till exempel när appen blir aktiv och i bakgrundsuppdateringen.
    public func fetchHouseholdChanges() async {
        await householdSync.fetchChanges()
        // Synken skickar inget nytt läge när inget har ändrats. Egna utställda från knappen i Live Activity skickas därför här.
        guard household.status == .synced, inHousehold else { return }
        await sendPendingMarks(in: household, today: StockholmClock.today(now: now()))
    }

    /// Knappen Utställt i Live Activity har sparat en bock i `placed-out.json`. För en delad adress skickas den till hushållet
    /// direkt, medan appen körs i bakgrunden, och inte först när appen öppnas.
    public func sendLiveActivityMarks() async {
        rereadHouseholdCacheIfNeeded()
        guard inHousehold, household.status == .synced else { return }
        await sendPendingMarks(in: household, today: StockholmClock.today(now: now()))
        // Hämtningen skickar också det som väntar.
        await householdSync.fetchChanges()
    }

    /// Med i ett hushåll: en roll, och inte borttagen.
    static func isMember(_ state: HouseholdState) -> Bool {
        state.role != .none && state.status != .removed
    }

    public var inHousehold: Bool { Self.isMember(household) }

    public func isShared(_ key: AddressKey) -> Bool {
        inHousehold && household.addresses.contains { $0.address.key == key }
    }

    /// Raden har visats. Ett borttaget hushåll visas då inte längre som läge, så att kortet inte står kvar.
    public func clearHouseholdNotice() {
        householdNotice = nil
        guard household.status == .removed else { return }
        household.status = .synced
        try? store.setHouseholdState(household)
        widgetReloader()
    }

    /// Raden "{namn} gick med i hushållet" och "{namn} är inte längre med i hushållet", efter varandra, eller `nil`.
    public var householdMembersText: String? {
        let joined = householdPreferences.joinedNames
        let left = householdPreferences.leftNames
        let parts = [joined.isEmpty ? nil : HouseholdTexts.joined(joined), left.isEmpty ? nil : HouseholdTexts.left(left)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }

    // MARK: Mitt namn

    /// Namnet i fältet Ditt namn: det jag har sparat, annars det som står i hushållet, annars förnamnet från Apple-kontot.
    public var householdName: String {
        householdPreferences.myName ?? household.myName ?? household.suggestedName ?? ""
    }

    /// Sant när jag är med i ett hushåll men inte har sparat något namn, så att de andra skulle se "Någon".
    public var householdNameMissing: Bool {
        inHousehold && (householdPreferences.myName ?? household.myName).map(Self.trimmed)?.isEmpty != false
    }

    /// Sparar mitt namn och skickar det till hushållet. Ett tomt namn sparas inte. Svarar med om namnet sparades lokalt;
    /// går det inte att skicka nu skickas det vid nästa synkade läge.
    @discardableResult
    public func setHouseholdName(_ name: String) async -> Bool {
        let cleaned = Self.trimmed(name)
        guard !cleaned.isEmpty else { return false }
        if householdPreferences.myName != cleaned {
            householdPreferences.myName = cleaned
            guard saveHouseholdPreferences() else {
                lastStorageError = "Kunde inte spara namnet. Inget har ändrats."
                return false
            }
        }
        if inHousehold, household.myName != cleaned {
            try? await householdSync.setMyName(cleaned)
        }
        return true
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Mitt sparade namn skickas till hushållet tills det står där. Har jag inget sparat men hushållet har ett, från en
    /// annan av mina enheter, används det.
    private func syncMyName(in state: HouseholdState) async {
        guard Self.isMember(state) else { return }
        if let wanted = householdPreferences.myName {
            if state.myName != wanted { try? await householdSync.setMyName(wanted) }
        } else if let existing = state.myName, !Self.trimmed(existing).isEmpty {
            householdPreferences.myName = existing
            saveHouseholdPreferences()
        }
    }

    /// Raden om vem som gått med eller inte längre är med har setts i arket Hushåll eller stängts på hemskärmen.
    public func clearMembersNotice() {
        guard !householdPreferences.joinedNames.isEmpty || !householdPreferences.leftNames.isEmpty else { return }
        householdPreferences.joinedNames = []
        householdPreferences.leftNames = []
        saveHouseholdPreferences()
    }

    /// En inbjudan är accepterad. När hushållet har kommit öppnas arket med raden om vems hushåll det är.
    public func expectHouseholdWelcome(ownerName: String) {
        pendingWelcomeOwner = ownerName
        // Deltagarna som redan är med när jag går med är inte nya.
        householdPreferences.knownParticipants = nil
        householdPreferences.joinedNames = []
        householdPreferences.leftNames = []
        householdPreferences.participantNames = [:]
        saveHouseholdPreferences()
    }

    /// Inbjudan gick inte att acceptera. Inget ark öppnas.
    public func cancelHouseholdWelcome() {
        pendingWelcomeOwner = nil
    }

    /// Arket Hushåll har öppnats efter en inbjudan.
    public func householdSheetShown() {
        householdSheetRequested = false
    }

    /// Identifieraren för notisen om att någon ställt ut. `NotificationDiff.isOwn` känner inte igen den.
    static func householdNotificationId(_ placedOut: PlacedOut) -> String {
        "hushall.\(placedOut.key.fileName).\(placedOut.date.iso)"
    }

    /// Bockar som inte passerat och läggs till de utställda när påminnelserna planeras. Mina egna, även från en annan enhet,
    /// räknas alltid. Andras räknas bara när Tysta min påminnelse är på.
    func householdSilenced(today: DayDate) -> Set<PlacedOut> {
        guard inHousehold else { return [] }
        var result: Set<PlacedOut> = []
        if let myId = household.myId {
            result.formUnion(household.marks.filter { $0.by == myId && $0.placedOut.date >= today }.map(\.placedOut))
        }
        if householdPreferences.silenceWhenOthersPlaceOut {
            result.formUnion(HouseholdLogic.othersActive(household.marks, myId: household.myId, today: today).map(\.placedOut))
        }
        return result
    }

    // MARK: Nytt läge

    /// Behandlar ett läge från synken: sparar det, slår ihop adresserna, skickar egna bockar, visar notiser och planerar om.
    func receiveHousehold(_ incoming: HouseholdState) async {
        defer { handledHouseholdStates += 1 }
        let today = StockholmClock.today(now: now())
        rereadHouseholdCacheIfNeeded()
        let previous = household

        if incoming.status == .removed || (incoming.role == .none && incoming.status == .synced) {
            adoptLeft(status: incoming.status, wasMember: Self.isMember(previous))
            return
        }

        let reliable = incoming.status == .synced
        var effective = incoming
        if !reliable {
            // Ett tekniskt fel får aldrig se ut som att hushållet, en adress eller en bock saknas. Det senast sparade gäller.
            if incoming.role == .none {
                effective = previous
                effective.status = incoming.status
            } else if householdCacheKnown {
                effective.addresses = previous.addresses
                effective.participants = previous.participants
                // Mina egna nya bockar, som väntar på att skickas, visas ändå. Andras gäller som de senast sparades.
                let myId = incoming.myId ?? previous.myId
                let known = Set(previous.marks.map(\.placedOut))
                effective.marks = previous.marks + incoming.marks.filter { $0.by == myId && !known.contains($0.placedOut) }
            }
        }

        // Utan läsbar cache vet appen inte vilka adresser som delades, så ett läge med fel ändrar inga adresser.
        var addedKeys: Set<AddressKey> = []
        var addressesChanged = false
        if Self.isMember(effective), reliable || householdCacheKnown {
            (addressesChanged, addedKeys) = mergeShared(effective.addresses)
        }

        household = effective
        if reliable || householdCacheKnown {
            // Lägget är bara en cache. Går det inte att spara görs det vid nästa läge.
            try? store.setHouseholdState(effective)
            householdCacheKnown = true
        }

        // Bara ett synkat läge går att lita på för att skicka, ta bort eller visa något.
        if reliable {
            if Self.isMember(previous), Self.isMember(effective) {
                adoptRemoteUndo(previous: previous, current: effective, today: today)
            }
            await sendPendingMarks(in: effective, today: today)
            await notifyOthersPlacedOut(in: effective, today: today)
            await noticeNewParticipants(in: effective)
            await syncMyName(in: effective)
            if let owner = pendingWelcomeOwner, Self.isMember(effective) {
                pendingWelcomeOwner = nil
                householdNotice = HouseholdTexts.welcome(ownerName: owner)
                householdSheetRequested = true
            }
        }
        pruneNotifiedMarks(today: today)

        if previous != effective || addressesChanged { applyReminders() }
        // Widgeten visar Utställt från `household.json`. Adresserna laddar om den själva i `mergeShared`.
        if previous.marks != effective.marks || previous.role != effective.role || previous.status != effective.status {
            widgetReloader()
        }
        // En ny adress från hushållet har inget schema än.
        if !addedKeys.isEmpty { await refreshAll(manual: false) }
        // En gång per dag, så att en post som inte går att ta bort inte ger en slinga av nya lägen.
        if reliable, Self.isMember(effective), lastRemoveExpiredDay != today, !HouseholdLogic.expired(effective.marks, today: today).isEmpty {
            lastRemoveExpiredDay = today
            await householdSync.removeExpired(today: today)
        }
    }

    /// Läser `household.json` igen om den inte gick att läsa vid start, till exempel skyddad data före upplåsning.
    func rereadHouseholdCacheIfNeeded() {
        guard !householdCacheKnown else { return }
        switch store.householdState() {
        case .value(let saved):
            household = saved
            householdCacheKnown = true
        case .missing:
            householdCacheKnown = true
        case .unreadable, .unavailable:
            break
        }
    }

    /// Lägger in delade adresser och tar bort mottagna som slutat delas. Svarar med om listan ändrades och vilka adresser som är nya.
    private func mergeShared(_ shared: [HouseholdAddress]) -> (changed: Bool, added: Set<AddressKey>) {
        // Går adresserna inte att läsa skrivs listan aldrig över.
        guard addressesReadable else { return (false, []) }
        let result = HouseholdLogic.merge(shared: shared, into: addresses, received: householdPreferences.receivedKeys)
        var changed = false
        var added: Set<AddressKey> = []
        if result.list != addresses {
            let before = Set(addresses.map(\.key))
            guard saveAddresses(result.list) else { return (false, []) }
            let after = Set(result.list.map(\.key))
            for key in before.subtracting(after) {
                schedules[key] = nil
                removeStoredSchedule(for: key)
            }
            added = after.subtracting(before)
            scheduleRevision += 1
            widgetReloader()
            changed = true
        }
        if result.received != householdPreferences.receivedKeys {
            householdPreferences.receivedKeys = result.received
            saveHouseholdPreferences()
        }
        return (changed, added)
    }

    /// Lämnat, borttagen eller avslutat hushåll: adresserna blir kvar som egna, bockarna försvinner och raden visas en gång.
    private func adoptLeft(status: HouseholdStatus, wasMember: Bool) {
        var left = HouseholdState.empty
        // Borttagen visas bara tillsammans med raden om det. Ett upprepat läge visar ingenting igen.
        left.status = status == .removed && !wasMember ? .synced : status
        let changed = household != left
        if changed {
            household = left
            try? store.setHouseholdState(left)
            householdCacheKnown = true
        }
        sentHouseholdMarks = []
        if !householdPreferences.receivedKeys.isEmpty || householdPreferences.knownParticipants != nil || !householdPreferences.joinedNames.isEmpty || !householdPreferences.leftNames.isEmpty {
            householdPreferences.receivedKeys = []
            // Ett nytt hushåll börjar utan kända deltagare, så att ingen räknas som ny när jag går med.
            householdPreferences.knownParticipants = nil
            householdPreferences.joinedNames = []
            householdPreferences.leftNames = []
            householdPreferences.participantNames = [:]
            saveHouseholdPreferences()
        }
        if wasMember { householdNotice = HouseholdTexts.leftNote }
        if changed {
            applyReminders()
            widgetReloader()
        }
    }

    /// En egen bock som fanns i hushållet och nu är borta har ångrats av någon annan. Då tas den bort även lokalt.
    private func adoptRemoteUndo(previous: HouseholdState, current: HouseholdState, today: DayDate) {
        guard case .value(let saved) = store.placedOutState() else { return }
        let before = Set(previous.marks.map(\.placedOut))
        let remaining = Set(current.marks.map(\.placedOut))
        // En bock som försvann med sin adress är inget Ångra.
        let sharedKeys = Set(current.addresses.map(\.address.key))
        for entry in Set(saved) where entry.date >= today && before.contains(entry) && !remaining.contains(entry) && sharedKeys.contains(entry.key) {
            // Ett skrivfel ger i värsta fall att bocken skickas igen vid nästa läge.
            try? store.unmarkPlacedOut(entry)
            sentHouseholdMarks.remove(entry)
        }
    }

    /// Egna utställda för delade adresser som saknar bock i hushållet, till exempel från knappen i Live Activity, skickas en gång.
    private func sendPendingMarks(in state: HouseholdState, today: DayDate) async {
        guard Self.isMember(state), case .value(let saved) = store.placedOutState() else { return }
        let sharedKeys = Set(state.addresses.map(\.address.key))
        let marked = Set(state.marks.map(\.placedOut))
        for entry in saved where entry.date >= today && sharedKeys.contains(entry.key) && !marked.contains(entry) {
            await sendMark(entry)
        }
    }

    private func sendMark(_ entry: PlacedOut) async {
        guard !sentHouseholdMarks.contains(entry) else { return }
        sentHouseholdMarks.insert(entry)
        do {
            try await householdSync.mark(entry)
        } catch {
            // Bocken står kvar i `placed-out.json` och skickas igen vid nästa läge.
            sentHouseholdMarks.remove(entry)
        }
    }

    /// En notis per ny bock från någon annan, när valet är på. Mina egna bockar, även från andra enheter, ger aldrig någon.
    private func notifyOthersPlacedOut(in state: HouseholdState, today: DayDate) async {
        guard householdPreferences.notifyWhenOthersPlaceOut, Self.isMember(state), let myId = state.myId else { return }
        let fresh = HouseholdLogic.othersActive(state.marks, myId: myId, today: today)
            .filter { !householdPreferences.notifiedMarks.contains($0.placedOut) }
        guard !fresh.isEmpty else { return }
        // Utan tillstånd visas ingen notis, och bocken visas inte heller senare när den redan är gammal.
        let allowed = await scheduler.authorization() == .authorized
        for mark in fresh {
            householdPreferences.notifiedMarks.insert(mark.placedOut)
            let addressName = addresses.first { $0.key == mark.placedOut.key }?.displayName
                ?? state.addresses.first { $0.address.key == mark.placedOut.key }?.address.displayName
            guard allowed, let addressName else { continue }
            let name = state.participants.first { $0.id == mark.by }?.name ?? "Någon"
            await scheduler.deliverNow(
                identifier: Self.householdNotificationId(mark.placedOut),
                title: HouseholdTexts.placedOutNotificationTitle,
                body: HouseholdTexts.othersPlacedOutNotification(name: name, address: addressName)
            )
        }
        saveHouseholdPreferences()
    }

    /// Deltagare som gått med eller inte längre är med sedan förra synkade läget ger raden på hemskärmen och i arket,
    /// och en notis när valet är på.
    /// Första gången hushållet ses, när jag själv gått med eller hämtar på nytt, blir deltagarna kända utan rad.
    private func noticeNewParticipants(in state: HouseholdState) async {
        guard Self.isMember(state) else { return }
        let known = householdPreferences.knownParticipants
        let fresh = HouseholdLogic.newParticipants(state.participants, known: known, myId: state.myId)
        let departed = HouseholdLogic.departedParticipants(state.participants, known: known, myId: state.myId)
        // Saknar listan mig är delningen inte hämtad. Då står de kända deltagarna kvar, så att ingen räknas som ny sedan.
        guard state.participants.contains(where: { $0.id == state.myId }) else { return }
        let ids = Set(state.participants.map(\.id))
        let names = Dictionary(state.participants.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let departedNames = departed.map { householdPreferences.participantNames[$0] ?? "Någon" }
        guard known != ids || !fresh.isEmpty || householdPreferences.participantNames != names else { return }
        householdPreferences.knownParticipants = ids
        householdPreferences.participantNames = names
        householdPreferences.joinedNames += fresh.map(\.name).filter { !householdPreferences.joinedNames.contains($0) }
        householdPreferences.leftNames += departedNames.filter { !householdPreferences.leftNames.contains($0) }
        saveHouseholdPreferences()
        guard !fresh.isEmpty || !departed.isEmpty, householdPreferences.notifyWhenOthersPlaceOut, await scheduler.authorization() == .authorized else { return }
        for participant in fresh {
            await scheduler.deliverNow(
                identifier: "hushall.deltagare.\(participant.id)",
                title: HouseholdTexts.membersNotificationTitle,
                body: HouseholdTexts.joined([participant.name])
            )
        }
        for (id, name) in zip(departed, departedNames) {
            await scheduler.deliverNow(
                identifier: "hushall.lamnade.\(id)",
                title: HouseholdTexts.membersNotificationTitle,
                body: HouseholdTexts.left([name])
            )
        }
    }

    /// Passerade bockar behöver inte kommas ihåg, så att listan inte växer.
    private func pruneNotifiedMarks(today: DayDate) {
        let kept = householdPreferences.notifiedMarks.filter { $0.date >= today }
        guard kept != householdPreferences.notifiedMarks else { return }
        householdPreferences.notifiedMarks = kept
        saveHouseholdPreferences()
    }

    /// Skriver valen från minnet. Ett skrivfel lämnar minnet orört, och nästa skrivning försöker igen.
    @discardableResult
    private func saveHouseholdPreferences() -> Bool {
        (try? store.setHouseholdPreferences(householdPreferences)) != nil
    }

    // MARK: Dela

    /// Delar adressen med hushållet eller slutar dela den. Svarar med om det gick.
    public func setShared(_ on: Bool, for key: AddressKey) async -> Bool {
        guard inHousehold else { return false }
        if on {
            guard let address = addresses.first(where: { $0.key == key }) else { return false }
            return (try? await householdSync.share(address)) != nil
        }
        // Den som själv slutar dela behåller adressen, även om den en gång kom från hushållet.
        let wasReceived = householdPreferences.receivedKeys.remove(key) != nil
        if wasReceived { saveHouseholdPreferences() }
        do {
            try await householdSync.unshare(key)
            return true
        } catch {
            if wasReceived {
                householdPreferences.receivedKeys.insert(key)
                saveHouseholdPreferences()
            }
            return false
        }
    }

    // MARK: Ställa ut

    /// Nästa tömning för adressen enligt det sparade schemat.
    private func nextPickupDate(for key: AddressKey, today: DayDate) -> DayDate? {
        guard let events = schedules[key]?.response?.events else { return nil }
        return ScheduleLogic.nextPickup(events, today: today)?.date
    }

    /// Ställer ut kärlen för nästa tömning: sparas i `placed-out.json` och, för en delad adress, som bock i hushållet.
    public func placeOut(_ key: AddressKey) async {
        let today = StockholmClock.today(now: now())
        guard let date = nextPickupDate(for: key, today: today) else { return }
        let entry = PlacedOut(key: key, date: date)
        do {
            try store.markPlacedOut(entry, today: today)
        } catch {
            lastStorageError = "Kunde inte spara att kärlen är utställda."
            return
        }
        applyReminders()
        guard isShared(key) else { return }
        if !household.marks.contains(where: { $0.placedOut == entry }) {
            await sendMark(entry)
        }
        widgetReloader()
    }

    /// Ångrar bocken för nästa tömning, min egen eller någon annans. Påminnelsen kommer tillbaka om tiden inte har passerat.
    public func undoPlaceOut(_ key: AddressKey) async {
        let today = StockholmClock.today(now: now())
        guard let date = nextPickupDate(for: key, today: today) else { return }
        let entry = PlacedOut(key: key, date: date)
        do {
            try store.unmarkPlacedOut(entry)
        } catch {
            lastStorageError = "Kunde inte ångra. Inget har ändrats."
            return
        }
        sentHouseholdMarks.remove(entry)
        // Live Activity får starta igen för samma tömning. Går det inte att spara startar den bara inte om.
        try? store.forgetActivity(entry)
        // Bocken tas bort i minnet direkt, så att påminnelsen kommer tillbaka utan att vänta på nästa läge.
        let hadMark = household.marks.contains { $0.placedOut == entry }
        household.marks.removeAll { $0.placedOut == entry }
        applyReminders()
        guard hadMark || isShared(key) else { return }
        if hadMark, householdCacheKnown {
            // Widgeten läser bocken från lagringen. Nästa läge från synken skriver över det här.
            try? store.setHouseholdState(household)
        }
        widgetReloader()
        do {
            try await householdSync.unmark(entry)
        } catch {
            householdNotice = HouseholdTexts.status(.failed)
        }
    }

    // MARK: Lämna

    /// Lämnar hushållet. Adresserna blir kvar som egna, och raden om det visas.
    public func leaveHousehold() async {
        guard household.role != .none else { return }
        let wasMember = inHousehold
        do {
            try await householdSync.leave()
        } catch {
            householdNotice = HouseholdTexts.status(.failed)
            return
        }
        // Läget från synken kan komma före eller efter. Raden visas ändå bara en gång.
        adoptLeft(status: .synced, wasMember: wasMember && inHousehold)
    }

    // MARK: Val

    /// Tysta min påminnelse när någon annan har ställt ut. Valet schemalägger aldrig något, det tar bara bort.
    public func setSilenceWhenOthersPlaceOut(_ on: Bool) {
        guard householdPreferences.silenceWhenOthersPlaceOut != on else { return }
        var updated = householdPreferences
        updated.silenceWhenOthersPlaceOut = on
        guard (try? store.setHouseholdPreferences(updated)) != nil else {
            lastStorageError = "Kunde inte spara inställningen. Inget har ändrats."
            return
        }
        householdPreferences = updated
        applyReminders()
    }

    /// Notiser från hushållet: när någon ställer ut kärlen och när någon går med. Kräver notistillstånd, och frågan ställs när valet slås på och tillståndet inte är avgjort.
    /// Bockar som redan finns när valet slås på ger ingen notis.
    public func setNotifyWhenOthersPlaceOut(_ on: Bool) async -> PermissionResult {
        if on {
            var status = await scheduler.authorization()
            if status == .notDetermined {
                status = await scheduler.requestAuthorization() ? .authorized : .denied
            }
            guard status == .authorized else { return .denied }
        }
        var updated = householdPreferences
        updated.notifyWhenOthersPlaceOut = on
        if on {
            let today = StockholmClock.today(now: now())
            updated.notifiedMarks.formUnion(HouseholdLogic.othersActive(household.marks, myId: household.myId, today: today).map(\.placedOut))
        }
        guard (try? store.setHouseholdPreferences(updated)) != nil else {
            lastStorageError = "Kunde inte spara inställningen. Inget har ändrats."
            return .failed
        }
        householdPreferences = updated
        return .granted
    }
}
