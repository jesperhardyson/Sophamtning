# Två påminnelser – genomförandeplan

> **För agenter:** Använd superpowers:subagent-driven-development (rekommenderas) eller superpowers:executing-plans, en uppgift i taget. Stegen har kryssrutor (`- [ ]`).

**Mål:** Påminnelsen kan komma kvällen före, samma morgon eller båda, med var sin tid. Live Activity får ett eget val för när den visas.

**Arkitektur:** `ReminderSettings` får `eveningOn`, `morningOn` och `liveActivityTiming` i stället för `timing`. `ReminderTime` räknar tiden per val, och planeraren gör en notis per påslaget val och tömning, med valet i notisens identifierare. Live Activity och reserven följer `liveActivityTiming`. All logik och alla texter ligger i `SophamtningKit` och testas med `swift test`. Appen ändrar inställningssidan och anropen.

**Teknik:** Swift 6, SwiftUI, iOS 26, Swift Testing, ActivityKit (bakom `LiveActivityScheduling`).

**Spec:** `docs/specs/2026-11-06-ios-app.md`, avsnitten **Påminnelser > Tid**, **Notiser**, **Live Activity** och **Samspel mellan notis och Live Activity**, och huvudkortets fot under **Skärmar**. Enhetsfallen 75–78 i `docs/specs/2026-11-06-enhetschecklista.md`.

## Förutsättningar

- Gren: `feature/tva-paminnelser`, i arbetskopian `/Users/jesper/Code/Sophamtning-tva-paminnelser`. Specen är redan committad där (`docs:`). Kodens PR heter `feat: Två påminnelser, kvällen före och samma morgon`.
- Varje uppgift slutar med att `swift test` i paketet är grönt och att appen bygger (kommandona i `CLAUDE.md`). Uppgift 1 lägger därför en tillfällig brygga i `AppModel`, så att appens nuvarande inställningssida fungerar tills Uppgift 5 byter ut den.

## Globala krav

- "I dag" och alla påminnelsetider räknas i `Europe/Stockholm`, med `StockholmClock`.
- Kvällen före: 15:00–23:00 i steg om 15 minuter, förval 18:00 (1080), på från början. Samma morgon: 05:00–09:00 i steg om 15 minuter, förval 06:00 (360), av från början. Minst ett val är alltid på.
- `liveActivityTiming` har förvalet `.eveningBefore`. Live Activity använder tiden för sitt val, också när notiserna för det valet är av.
- Notiser och Live Activity är av från början. Att slå på ett val schemalägger notiser bara för adresser där notiser redan är på.
- Texterna följer specen ordagrant:
  - reglaget heter "Påminn mig"
  - VoiceOver säger "Slå på påminnelse" och "Stäng av påminnelse"
  - raden Påminnelse visar "Kvällen före, 18:00", "Samma morgon, 06:00" eller "18:00 och 06:00"
  - texten under delen Kvällen före är "Dagen före tömningen, mellan 15:00 och 23:00."
  - texten under delen Samma morgon är "Samma dag som tömningen, mellan 05:00 och 09:00. Minst en påminnelse är på. Notiser slår du på och av per adress."
- Taket på 60 notiser står kvar och räknar varje notis.
- All text och alla kommentarer är på svenska. Nytt beteende testas som enhetstester i paketet. Inga nya UI-tester.

## Granskningsfokus

1. **Uppgradering med väntande notiser.** Den som hade samma morgon har väntande notiser med den gamla identifieraren (`<fil>-<datum>`). Efter uppdateringen ska de tas bort och ersättas av `-morgon`-notiser, inte ligga kvar som dubbletter. Kvällens identifierare är oförändrad, så kvällsanvändare får inga nya schemaläggningar. Testas i Uppgift 2.
2. **Båda valen på och aktiviteten på kvällen har syns.** Kvällens notis hoppas över, men morgonens notis för samma tömning ska ändå komma. Testas i Uppgift 3.
3. **Utställt med båda valen på.** `PlacedOutAction` ska ta bort både kvällens och morgonens väntande notis. Annars kommer morgonens notis trots bocken. Testas i Uppgift 2.
4. **Det sista valet går inte att stänga av.** Det gäller också en sparad fil där båda valen är av, som ska läsas som att bara kvällen är på. Testas i Uppgift 1 och 5.
5. **Bock från hushållet mellan kvällen och morgonen.** Morgonens notis försvinner. Ångras bocken före morgonens tid kommer bara morgonens notis tillbaka, eftersom kvällens har passerat. Testas i Uppgift 3.

---

### Uppgift 1: Inställningarna och tidsfunktionen

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Storage/StoredModels.swift` (`ReminderTiming`, `ReminderSettings`)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderTime.swift`
- Ändra (brygga): `ReminderPlanner.swift`, `HomeContent.swift`, `AddressDetail.swift`, `AppModel.swift` och appens `SettingsView.swift`, `AddressView.swift` och `AddressQuickActions.swift`
- Test: `LocalStoreTests.swift`, `ReminderTimeTests.swift` och alla tester som skapar `ReminderSettings(timing:)`

**Gränssnitt:**
- Skapar i `ReminderSettings`:
  - `var eveningOn: Bool` (förval `true`), `var morningOn: Bool` (förval `false`) och `var liveActivityTiming: ReminderTiming` (förval `.eveningBefore`). `timing` och `activeMinutes` tas bort.
  - `init(eveningOn:morningOn:reminderMinutes:morningMinutes:liveActivityTiming:liveActivityOn:reminderOfferShown:)`, alla med förval.
  - `func minutes(for timing: ReminderTiming) -> Int`: den sparade tiden för valet om den är giltig, annars `timing.defaultMinutes`.
  - `func isEnabled(_ timing: ReminderTiming) -> Bool`.
  - `var enabledTimings: [ReminderTiming]`: påslagna val i ordningen kväll, morgon. Den är aldrig tom.
  - `var settingsValue: String` med specens tre former.
- Skapar i `ReminderTime`:
  - `static func date(forPickup: DayDate, timing: ReminderTiming, settings: ReminderSettings) -> Date`. Den gamla `date(forPickup:settings:)` tas bort.
  - `public struct UpcomingReminder: Equatable, Sendable { let pickup: DayDate; let timing: ReminderTiming; let date: Date }`.
  - `static func next(events: [PickupEvent], settings: ReminderSettings, now: Date) -> UpcomingReminder?`: den tidigaste påminnelsen efter `now`, över kommande tömningar med fraktioner och alla påslagna val.

- [ ] **Steg 1: Skriv testerna som ska falla**

```swift
@Test func gammalKvällLäses() throws {
    let s = try decode(#"{"timing":"eveningBefore","reminderMinutes":1140,"morningMinutes":420,"liveActivityOn":true}"#)
    #expect(s.eveningOn && !s.morningOn && s.liveActivityTiming == .eveningBefore)
    #expect(s.minutes(for: .eveningBefore) == 1140 && s.minutes(for: .sameMorning) == 420)
}
@Test func gammalMorgonLäses() throws {
    let s = try decode(#"{"timing":"sameMorning","reminderMinutes":1080,"morningMinutes":420,"liveActivityOn":false}"#)
    #expect(!s.eveningOn && s.morningOn && s.liveActivityTiming == .sameMorning)
}
@Test func utanTimingOchOkändTimingBlirKväll() throws {
    #expect(try decode(#"{"reminderMinutes":1080,"liveActivityOn":false}"#).enabledTimings == [.eveningBefore])
    #expect(try decode(#"{"timing":"lunch","reminderMinutes":1080,"liveActivityOn":false}"#).enabledTimings == [.eveningBefore])
}
@Test func bådaAvLäsesSomKväll() throws {
    let s = try decode(#"{"eveningOn":false,"morningOn":false,"reminderMinutes":1080,"liveActivityOn":false}"#)
    #expect(s.enabledTimings == [.eveningBefore])
}
@Test func nyaFältenSparasOchTimingSkrivsInte() throws {
    let s = ReminderSettings(eveningOn: true, morningOn: true, morningMinutes: 420, liveActivityTiming: .sameMorning)
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(ReminderSettings.self, from: data) == s)
    #expect(!String(decoding: data, as: UTF8.self).contains("\"timing\""))
}
@Test func ogiltigTidGerFörval() {
    let s = ReminderSettings(reminderMinutes: 5, morningMinutes: 1000)
    #expect(s.minutes(for: .eveningBefore) == 1080 && s.minutes(for: .sameMorning) == 360)
}
@Test func värdetPåRaden() {
    #expect(ReminderSettings().settingsValue == "Kvällen före, 18:00")
    #expect(ReminderSettings(eveningOn: false, morningOn: true).settingsValue == "Samma morgon, 06:00")
    #expect(ReminderSettings(morningOn: true, morningMinutes: 420).settingsValue == "18:00 och 07:00")
}
@Test func nästaPåminnelse() {
    let s = ReminderSettings(morningOn: true)
    let events = [event("2026-11-11", ["rest"])]
    #expect(ReminderTime.next(events: events, settings: s, now: stockholm("2026-11-10T12:00"))
        == .init(pickup: day("2026-11-11"), timing: .eveningBefore, date: stockholm("2026-11-10T18:00")))
    #expect(ReminderTime.next(events: events, settings: s, now: stockholm("2026-11-10T19:00"))?.timing == .sameMorning)
    #expect(ReminderTime.next(events: events, settings: s, now: stockholm("2026-11-11T07:00")) == nil)
}
```

`decode` är en lokal hjälpfunktion med `JSONDecoder`. De befintliga testerna som skapar `ReminderSettings(timing: .sameMorning, …)` skrivs om till `eveningOn: false, morningOn: true, liveActivityTiming: .sameMorning`. `timing: .eveningBefore` stryks. `activeMinutes` byts mot `minutes(for:)`. Kontrollera att varje omskrivet test behåller sitt värde.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "LocalStore|ReminderTime"`
Förväntat: kompileringsfel, eftersom de nya fälten och funktionerna saknas.

- [ ] **Steg 3: Byt fälten, avkodningen och `ReminderTime`**

`timing` läses med en egen `CodingKey` i `init(from:)` och används bara när `eveningOn` och `morningOn` saknas. `encode(to:)` skriver inte `timing`. Är båda valen falska efter läsningen blir `eveningOn` sant. Kommentaren på `ReminderTiming` ("Aldrig båda") ändras till att typen anger ett av valen.

- [ ] **Steg 4: Brygga för de andra anropen**

Där koden läser `settings.timing` används `settings.liveActivityTiming`, och där den läser `activeMinutes` används `settings.minutes(for: settings.liveActivityTiming)`. `ReminderTime.date(forPickup:settings:)` byts mot samma funktion med `timing: settings.liveActivityTiming`. I `AppModel` får `setReminderTiming(_:)` sätta `eveningOn`, `morningOn` och `liveActivityTiming` så att bara det valda är på, och `setReminderMinutes(_:)` sparar tiden för `liveActivityTiming`. Båda märks med kommentaren `// Brygga: ersätts i Uppgift 5.` Det ger samma beteende som i dag för den som har ett val. Uppgift 2–5 tar bort bryggan.

- [ ] **Steg 5: Kör testerna och bygg**

Kör: `cd iOS/Packages/SophamtningKit && swift test`, och sedan bygget av appen.
Förväntat: allt är grönt och bygget lyckas.

- [ ] **Steg 6: Committa**

```bash
git commit -am "feat: Kvällen före och samma morgon kan vara på samtidigt i inställningarna"
```

---

### Uppgift 2: Identifierare per val

**Filer:**
- Ändra: `ReminderPlanner.swift` (`PlannedNotification.identifier`), `NotificationDiff.swift` (`isOwn`), `PlacedOutAction.swift`
- Test: `NotificationDiffTests.swift`, `PlacedOutTests.swift`

**Gränssnitt:**
- `PlannedNotification.identifier(key: AddressKey, date: DayDate, timing: ReminderTiming) -> String`. Kvällen ger `"<key.fileName>-<iso>"` som i dag, och morgonen ger `"<key.fileName>-<iso>-morgon"`. Den gamla signaturen utan `timing` tas bort. Anropen i planeraren får `timing: input.settings.liveActivityTiming` tills Uppgift 3.
- `NotificationDiff.isOwn(identifier:)` godtar båda formerna och inget annat.
- `PlacedOutAction.perform` anropar `cancelReminder` en gång per val, för både kvällen och morgonen.

- [ ] **Steg 1: Skriv testerna som ska falla**

- `morgonensIdentifierare`: `identifier(key:date:timing: .sameMorning)` slutar på `"-2026-11-11-morgon"`, och `.eveningBefore` ger samma sträng som före ändringen.
- `egnaIdentifierare`: `isOwn` är sant för `"<64 hex>-2026-11-11"` och `"<64 hex>-2026-11-11-morgon"`. Det är falskt för `"<64 hex>-2026-11-11-kvall"`, `"<64 hex>-2026-11-11-"` och `"<64 hex>-morgon"`.
- `gammalMorgonnotisErsätts` (Granskningsfokus 1): `pendingIds` innehåller `"<hex>-2026-11-11"` kl. 06:00, och `desired` har bara morgonens notis för samma dag. Diffen tar bort den gamla och lägger till `-morgon`.
- `utställtTarBortBåda` (Granskningsfokus 3): `perform` med en `cancelReminder` som samlar identifierarna ger exakt de två identifierarna för tömningen.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "NotificationDiff|PlacedOut"`
Förväntat: kompileringsfel på `identifier(key:date:timing:)`.

- [ ] **Steg 3: Ändra identifieraren, `isOwn` och `PlacedOutAction`**

Uppdatera dokumentationskommentarerna som beskriver formatet `<key.fileName>-<iso-datum>`.

- [ ] **Steg 4: Kör testerna och bygg**

Kör: `cd iOS/Packages/SophamtningKit && swift test`, och sedan bygget av appen.
Förväntat: allt är grönt.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: Kvällens och morgonens notis har var sin identifierare"
```

---

### Uppgift 3: Planeraren gör en notis per val

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderPlanner.swift` (`plan`, `retainable`, `planLiveActivity`)
- Test: `ReminderPlannerTests.swift`

**Gränssnitt:**
- Använder: `settings.enabledTimings`, `ReminderTime.date(forPickup:timing:settings:)` och `PlannedNotification.identifier(key:date:timing:)`.
- `retainable` ger fortfarande `[String: PlacedOut]`, nu med en nyckel per val vars ordinarie tid har passerat.
- `planLiveActivity` använder `settings.liveActivityTiming` överallt där den i dag läser `settings.timing`.

Regeln för notiser: för varje adress med notiser på, varje tömning som inte är utställd och varje påslaget val skapas en notis med valets tid. Reserven gäller bara notisen vars val är `liveActivityTiming`. Är aktiviteten för tömningen redan visad hoppas just den notisen över, och annars flyttas den till `fallbackDate(start:)`. Notisen för det andra valet påverkas inte av aktiviteten.

- [ ] **Steg 1: Skriv testerna som ska falla**

Använd testfilens hjälpfunktioner `schedule`, `event` och `stockholm`, och tömningen den 11 november 2026 på huvudadressen.

- `bådaValenGerTvåNotiser`: `ReminderSettings(morningOn: true)` och `now` 2026-11-10 12:00. Två notiser för den 11:e, kl. 18:00 den 10:e och kl. 06:00 den 11:e, med olika identifierare.
- `kvällenPasseradMorgonenKvar`: samma, men `now` är 19:00 den 10:e. Bara morgonens notis kommer.
- `bockMellanKvällOchMorgon` (Granskningsfokus 5): `now` är 19:00 och `placedOut` innehåller (hem, 11 nov). Ingen notis. Utan bocken kommer morgonens.
- `reservenGällerAktivitetensVal` (Granskningsfokus 2): båda valen på och `liveActivityTiming: .eveningBefore`. Aktiviteten finns och har start 18:00 den 10:e. Kvällens notis blir reserv kl. 18:45 med `fallbackTitle`, och morgonens kommer kl. 06:00 med `ordinaryTitle`. Med aktiviteten i `shownActivities` kommer bara morgonens.
- `ingenReservUtanAktivitetensVal`: bara kvällen på och `liveActivityTiming: .sameMorning`. Aktiviteten finns och har start 06:00 den 11:e. Kvällens notis kommer kl. 18:00 med `ordinaryTitle`, och ingen notis ligger kl. 06:45.
- `aktivitetenFöljerSittVal`: `ReminderSettings(eveningOn: true, morningOn: false, liveActivityTiming: .sameMorning, liveActivityOn: true)`. Aktiviteten har start 06:00 den 11:e.
- `taketRäknarVarjeNotis`: båda valen på och 40 kommande tömningar. Det blir exakt 60 notiser, de närmaste först.
- `retainablePerVal`: båda valen på och `now` 19:00 den 10:e. Bara kvällens identifierare finns i `retainable`.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter ReminderPlanner`
Förväntat: de nya testerna faller, eftersom planeraren gör en notis per tömning.

- [ ] **Steg 3: Ändra `plan`, `retainable` och `planLiveActivity` enligt regeln ovan**

- [ ] **Steg 4: Kör testerna och bygg**

Kör: `cd iOS/Packages/SophamtningKit && swift test`, och sedan bygget av appen.
Förväntat: allt är grönt.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: En notis per påslaget val och tömning"
```

---

### Uppgift 4: Texterna

**Filer:**
- Ändra: `ReminderTimingTexts.swift`, `HomeContent.swift` (`reminderTitle`, `reminderActionTitle`, `PrimaryReminder`, `reminderText`), `AddressDetail.swift` (`liveActivityText`, `missedReminder`, `reminderText`) och `AppModel.swift` (`missedReminderApplies`)
- Test: `ReminderTimingTextsTests.swift`, `HomeContentTests.swift`, `AddressDetailTests.swift` och `AppModelRemindersTests.swift`

**Gränssnitt:**
- `HomeContent.reminderTitle() -> String` ger "Påminn mig". `HomeContent.reminderActionTitle(isOn: Bool) -> String` ger "Stäng av påminnelse" eller "Slå på påminnelse". Parametern `timing` försvinner, och `ReminderTiming.toggleTitle` och `actionTitle` tas bort. `PrimaryReminder.init` förlorar `timing:`.
- `ReminderTiming.sectionFooter: String` innehåller specens två texter under delarna. `settingsFooter` tas bort i Uppgift 5, när vyn inte längre använder den.
- `ReminderSettings.latestTiming: ReminderTiming` är `enabledTimings.last!`, alltså morgonen när den är på.
- Raden under reglaget och huvudkortets text använder `ReminderTime.next`. Tiden är `next.date` och dagen är `StockholmClock.today(now: next.date)`.
- `missedReminder` och `missedReminderApplies` räknar med `latestTiming`.
- `liveActivityText` använder `liveActivityTiming` och `minutes(for: liveActivityTiming)`.

Regler för huvudkortets fot när en väntande aktivitet har start efter `now`: notiserna är på och `ReminderTime.next` ligger före starten (minst en minut före) ger "Påminnelse {veckodag} kl. {tid}". Notiserna är på och nästa påminnelse har samma minut som starten ger "Notis och Live Activity …". Annars blir det "Live Activity …". Finns ingen kommande tömning efter tiderna visar raden under reglaget texten för varje påslaget val i ordning, till exempel "Kvällen före varje tömning kl. 18:00. Samma morgon som varje tömning kl. 06:00."

- [ ] **Steg 1: Skriv testerna som ska falla**

- `reglagetsNamn`: `reminderTitle() == "Påminn mig"`, `reminderActionTitle(isOn: true) == "Stäng av påminnelse"` och `reminderActionTitle(isOn: false) == "Slå på påminnelse"`.
- `delarnasTexter`: `sectionFooter` för båda valen är exakt specens text.
- `radenVisarNästa`: båda valen på och tömning den 11:e. Klockan 12:00 den 10:e är texten "Tisdag kl. 18:00 inför onsdagens tömning." och klockan 19:00 "Onsdag kl. 06:00, samma dag som tömningen."
- `passeradMedBåda`: båda valen på och `now` 07:00 den 11:e. `missedReminder` ger "Tömning i dag. Påminnelsen för i morse har redan passerat." Klockan 19:00 den 10:e ger den `nil`.
- `passeradBaraKväll`: bara kvällen och `now` 19:00 den 10:e ger "Tömning i morgon. Påminnelsen för i kväll har redan passerat."
- `fotenNotisFöreAktivitet`: notiserna har båda valen på, och aktiviteten är väntande med start 06:00 den 11:e. Klockan 12:00 den 10:e är huvudkortets text "Påminnelse tisdag kl. 18:00". Med bara morgonen på är den "Notis och Live Activity onsdag kl. 06:00".
- `liveActivityTextFöljerSittVal`: bara kvällen på och `liveActivityTiming: .sameMorning` ger "Visas på låsskärmen från kl. 06:00 samma morgon."
- I `AppModelRemindersTests`, `missedGällerSenasteValet`: båda valen på och `now` 19:00 kvällen före. `missedReminderText` är `nil`.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "ReminderTimingTexts|HomeContent|AddressDetail|AppModelReminders"`
Förväntat: kompileringsfel och fallande tester.

- [ ] **Steg 3: Ändra texterna och reglerna enligt gränssnittet**

Byt appens anrop i `AddressView.swift` och `AddressQuickActions.swift` till de nya signaturerna. Byt också etiketten i `SophamtningUITests/CoreFlowTests.swift` (rad 86) till "Påminn mig".

- [ ] **Steg 4: Kör testerna och bygg**

Kör: `cd iOS/Packages/SophamtningKit && swift test`, och sedan bygget av appen.
Förväntat: allt är grönt.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: Texterna visar nästa påminnelse när båda valen är på"
```

---

### Uppgift 5: Inställningarna i AppModel och på sidan

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/App/AppModel.swift`
- Ändra: `iOS/Sophamtning/Views/SettingsView.swift`
- Ändra: `ReminderTimingTexts.swift` (ta bort `settingsFooter` och `settingsValue(minutes:)`)
- Test: `AppModelRemindersTests.swift` och `AppModelLiveActivityTests.swift`

**Gränssnitt:**
- `setReminder(_ timing: ReminderTiming, on: Bool) -> Bool`: sparar och planerar om. Ett försök att stänga av det sista påslagna valet ger `false` och ändrar inget. Inga stoppade aktiviteter glöms.
- `setReminderMinutes(_ minutes: Int, for timing: ReminderTiming) -> Bool`: en ogiltig tid ger `false`. `forgetStoppedActivities()` körs bara när `timing == settings.liveActivityTiming`.
- `setLiveActivityTiming(_ timing: ReminderTiming) -> Bool`: samma val ger `true` utan att något händer. Annars sparas valet, `forgetStoppedActivities()` körs och påminnelserna planeras om.
- `setReminderTiming(_:)` och bryggan från Uppgift 1 tas bort.
- `SettingsRoute` får `.times(ReminderTiming)` och `.liveActivityTiming`.

Sidan: raden **Påminnelse** visar `settings.settingsValue` och öppnar `ReminderTimeView`. Där står två delar, **Kvällen före** och **Samma morgon**. Varje del har ett `Toggle` med valets namn, och när reglaget är på raden **Tid** med klockslaget (`SettingsRow`), som öppnar `.times(timing)`. Det är en lista med `ChoiceRow` för `timing.times`, som i dag. Reglaget är `.disabled` när det är det enda som är på. Under varje del står `timing.sectionFooter`. Under `LiveActivityToggleRow` står, när Live Activity är på, raden **Visas från** med `liveActivityTiming.title`. Den öppnar `.liveActivityTiming`, en lista med två `ChoiceRow`. Texten med `settingsFooter` under delen Påminnelser på huvudsidan tas bort. Felkortet från `lastStorageError` står kvar överst, som i dag.

- [ ] **Steg 1: Skriv testerna som ska falla**

- `sistaValetGårInteAttStängaAv` (Granskningsfokus 4): med bara kvällen på ger `setReminder(.eveningBefore, on: false)` `false`, och inställningen är oförändrad. Med båda på går det, och kvällens notiser tas bort vid nästa planering.
- `morgonSlåsPå`: en adress har notiser på. `setReminder(.sameMorning, on: true)` schemalägger morgonens notiser. En adress med notiser av får inga.
- `tidFörValet`: `setReminderMinutes(420, for: .sameMorning)` ändrar `morningMinutes`, och `setReminderMinutes(420, for: .eveningBefore)` ger `false`.
- I `AppModelLiveActivityTests`, `bytAvAktivitetensValGlömmerStoppade`: en tömning finns i `ended`. `setLiveActivityTiming(.sameMorning)` tömmer listan. `setReminderMinutes(1140, for: .eveningBefore)` med `liveActivityTiming: .sameMorning` gör det inte.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "AppModelReminders|AppModelLiveActivity"`
Förväntat: kompileringsfel på de nya funktionerna.

- [ ] **Steg 3: Lägg till funktionerna i `AppModel` och ta bort bryggan**

- [ ] **Steg 4: Bygg om `ReminderTimeView` och lägg till Visas från i `SettingsView.swift` enligt beskrivningen ovan**

- [ ] **Steg 5: Kör testerna, bygg och kör det berörda UI-testet**

Kör: `cd iOS/Packages/SophamtningKit && swift test`, sedan bygget av appen och därefter `-only-testing:SophamtningUITests/CoreFlowTests` (påminnelseflödet). Stäng simulatorn efteråt.
Förväntat: allt är grönt.

- [ ] **Steg 6: Committa**

```bash
git commit -am "feat: Två påminnelser och eget val för Live Activity på inställningssidan"
```

---

### Uppgift 6: Avslutande kontroll

- [ ] **Steg 1:** Sök efter rester: `grep -rn "\.timing\b\|activeMinutes\|setReminderTiming\|toggleTitle\|settingsFooter\|Påminn mig kvällen före" iOS --include='*.swift'`. Förväntat: inga träffar utom `ReminderTiming` som typ.
- [ ] **Steg 2:** Kör hela UI-sviten en gång och schemat `Granskning`, enligt `CLAUDE.md`, innan PR:en görs redo.
- [ ] **Steg 3:** Driftsätt på Jespers iPhone och gå igenom enhetsfallen 75–78.
