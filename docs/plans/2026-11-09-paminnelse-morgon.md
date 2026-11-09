# Påminnelse på morgonen – genomförandeplan

> **För agenter:** Använd superpowers:executing-plans (native) eller superpowers:subagent-driven-development, en uppgift i taget. Stegen har kryssrutor (`- [ ]`).

**Mål:** Påminnelsen kan komma samma morgon som tömningen i stället för kvällen före. Valet gäller notiser, Live Activity, reserven och alla texter.

**Arkitektur:** Ett nytt fält `timing` i `ReminderSettings` och en enda tidsfunktion, `ReminderTime`, som planeraren, Live Activity, reserven och texterna använder. All logik och alla texter ligger i `SophamtningKit` och testas med `swift test`. Appen ändrar bara inställningssidan och läser texterna från paketet.

**Teknik:** Swift 6, SwiftUI, iOS 26, Swift Testing, ActivityKit (bakom `LiveActivityScheduling`).

**Spec:** `docs/specs/2026-11-06-ios-app.md`, avsnittet **Påminnelser > Tid** och reservnotisen under **Live Activity**.

## Förutsättningar

- Koden byggs på `main` först när UX-PR:erna #49–#58 och `feature/hushall` är mergade. Planen utgår från namnen de inför: `HomeContent.reminderTitle`, `HomeContent.reminderActionTitle(isOn:)` (#50) och `ReminderSettings.reminderOfferShown` med egen `init(from:)` (#53).
- Ny gren från `main`: `feature/paminnelse-morgon-kod`. Specen och planen mergas med #59 först, som `docs:`. Kodens PR heter `feat: Påminnelse på morgonen`.
- Innan Uppgift 1: läs `git log main -- iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderPlanner.swift`. Har hushållet ändrat hur `placedOut` byggs är det bara indata. Planeraren ska inte veta något om hushållet.

## Globala krav

- "I dag" och alla påminnelsetider räknas i `Europe/Stockholm`, med `StockholmClock`.
- Kvällen före: 15:00–23:00 i steg om 15 minuter, förval 18:00 (1080). Samma morgon: 05:00–09:00 i steg om 15 minuter, förval 06:00 (360).
- Inställningar sparade före fälten läses som `eveningBefore`, `reminderMinutes` som det var och `morningMinutes` 360.
- En ogiltig sparad tid ger förvalet för det valda alternativet, aldrig ett annat klockslag.
- Notiser och Live Activity är av från början. Byte av val schemalägger inget nytt utöver det som redan är påslaget.
- Texterna följer specens tabell ordagrant. All text och alla kommentarer är på svenska.
- Nytt beteende testas som enhetstester i paketet. Inga nya UI-tester.

## Granskningsfokus

1. **Byte av val med en väntande Live Activity.** En väntande aktivitet för kvällen före ska ersättas av en för morgonen, inte stå kvar. Det följer av att `start` ändras, och `LiveActivityDiff` byter redan vid ändrad start. Testas i Uppgift 3.
2. **Tömningsdagen efter 12:00 med samma morgon.** Nästa tömning gäller då, och en pågående aktivitet för i dag lever kvar tills Utställt eller systemets gräns. Testas i Uppgift 3.
3. **Tömning i dag och i morgon, båda med morgonval.** Klockan 07:00 med tiden 06:00 har dagens påminnelse passerat. Morgondagens ska ändå schemaläggas, och texten under reglaget ska gälla morgondagen. Testas i Uppgift 2 och 4.
4. **Gammal inställningsfil med ogiltig kvällstid och morgonval.** Morgontiden ska gälla oberoende av en trasig kvällstid. Testas i Uppgift 1.
5. **Bock från hushållet på tömningsdagen med morgonval.** Bocken tar bort dagens notis och aktivitet. Ångras den före tiden kommer notisen tillbaka. Testas i Uppgift 2.

---

### Uppgift 1: Valet i inställningarna och tidsfunktionen

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Storage/StoredModels.swift`
- Skapa: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderTime.swift`
- Test: `iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/LocalStoreTests.swift`, `.../ReminderTimeTests.swift` (ny)

**Gränssnitt:**
- Skapar:
  - `public enum ReminderTiming: String, Codable, Sendable, CaseIterable { case eveningBefore, sameMorning }`
  - `ReminderSettings.timing: ReminderTiming` (förval `.eveningBefore`) och `ReminderSettings.morningMinutes: Int` (förval 360). Initieraren får parametrarna `timing:` och `morningMinutes:` med förval.
  - `ReminderSettings.isValid(minutes: Int, for timing: ReminderTiming) -> Bool`. Den gamla `isValid(minutes:)` tas bort, och anropen byts till `for: .eveningBefore` eller `for: settings.timing`.
  - `ReminderSettings.activeMinutes: Int`: tiden för det valda alternativet om den är giltig, annars förvalet för alternativet.
  - `ReminderTiming.defaultMinutes: Int` (1080 eller 360) och `ReminderTiming.times: [Int]` (alla giltiga tider i ordning).
  - `public enum ReminderTime`:
    - `static func reminderDay(forPickup pickup: DayDate, timing: ReminderTiming) -> DayDate` ger dagen före eller samma dag.
    - `static func pickupDay(remindedOn day: DayDate, timing: ReminderTiming) -> DayDate` gör det omvända.
    - `public static func date(forPickup pickup: DayDate, settings: ReminderSettings) -> Date` ger `StockholmClock.date(on: reminderDay, minutes: settings.activeMinutes)`.

- [ ] **Steg 1: Skriv testerna som ska falla**

```swift
@Test func gamlaInställningarLäsesSomKvällenFöre() throws {
    let json = #"{"reminderMinutes":1140,"liveActivityOn":true}"#
    let s = try JSONDecoder().decode(ReminderSettings.self, from: Data(json.utf8))
    #expect(s.timing == .eveningBefore)
    #expect(s.reminderMinutes == 1140)
    #expect(s.morningMinutes == 360)
}

@Test func bådaTidernaSparas() throws {
    let s = ReminderSettings(timing: .sameMorning, reminderMinutes: 1200, morningMinutes: 420)
    let back = try JSONDecoder().decode(ReminderSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test(arguments: [(285, false), (300, true), (540, true), (555, false), (310, false), (1080, false)])
func giltigMorgontid(m: Int, ok: Bool) { #expect(ReminderSettings.isValid(minutes: m, for: .sameMorning) == ok) }

@Test func trasigKvällstidPåverkarInteMorgonen() {
    let s = ReminderSettings(timing: .sameMorning, reminderMinutes: 5, morningMinutes: 420)
    #expect(s.activeMinutes == 420)
    #expect(ReminderSettings(timing: .sameMorning, morningMinutes: 1000).activeMinutes == 360)
    #expect(ReminderSettings(reminderMinutes: 5).activeMinutes == 1080)
}

@Test func tidFörTömning() {
    let evening = ReminderSettings(reminderMinutes: 1080)
    let morning = ReminderSettings(timing: .sameMorning, morningMinutes: 360)
    #expect(ReminderTime.date(forPickup: day("2026-11-11"), settings: evening) == stockholm("2026-11-10T18:00"))
    #expect(ReminderTime.date(forPickup: day("2026-11-11"), settings: morning) == stockholm("2026-11-11T06:00"))
    // Sommartiden slutar 2026-10-25, så klockslaget ska stå kvar i svensk tid.
    #expect(ReminderTime.date(forPickup: day("2026-10-26"), settings: evening) == stockholm("2026-10-25T18:00"))
    #expect(ReminderTime.pickupDay(remindedOn: day("2026-11-10"), timing: .eveningBefore) == day("2026-11-11"))
    #expect(ReminderTime.pickupDay(remindedOn: day("2026-11-10"), timing: .sameMorning) == day("2026-11-10"))
}
```

Det befintliga testet för `isValid(minutes:)` i `LocalStoreTests.swift` skrivs om till `isValid(minutes:for: .eveningBefore)`, med samma värden.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "ReminderTime|LocalStore"`
Förväntat: kompileringsfel, eftersom `ReminderTiming`, `morningMinutes` och `ReminderTime` saknas.

- [ ] **Steg 3: Lägg till fälten och `ReminderTime`**

I `init(from:)` (finns från #53) läses `timing` och `morningMinutes` med `decodeIfPresent`, med förvalen ovan. En okänd text i `timing` ger `.eveningBefore`, så att en fil från en senare version inte gör inställningarna oläsliga.

- [ ] **Steg 4: Kör testerna**

Kör: `cd iOS/Packages/SophamtningKit && swift test`
Förväntat: alla gröna. Ett kompileringsfel där `isValid(minutes:)` anropas rättas med `for: .eveningBefore` i dag. Uppgift 2–4 byter sedan till rätt alternativ.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: Val mellan kvällen före och samma morgon i inställningarna"
```

---

### Uppgift 2: Planeraren och reserven följer valet

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderPlanner.swift`
- Test: `iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/ReminderPlannerTests.swift`

**Gränssnitt:**
- Använder: `ReminderTime.date(forPickup:settings:)` och `ReminderSettings.activeMinutes`.
- Skapar: `ReminderPlanner.fallbackDate(start: Date, timing: ReminderTiming) -> Date`. Taket är 23:45 för kvällen och 12:00 (720) för morgonen, samma dag som starten. `effectiveMinutes` och `defaultReminderMinutes` tas bort.

- [ ] **Steg 1: Skriv testerna som ska falla**

Använd testfilens hjälpfunktioner `schedule`, `event` och `stockholm`, och en `PlannerInput` med `settings: ReminderSettings(timing: .sameMorning, morningMinutes: 360)`.

- `morgonNotisSammaDag`: tömning 2026-11-11. Notisen har `fireDate == stockholm("2026-11-11T06:00")`.
- `morgonPasseradHoppasÖver`: `now = stockholm("2026-11-11T07:00")`, tömning 11 och 12 nov. Bara notisen för den 12:e kommer, kl. 06:00 samma dag.
- `morgonBockTystar`: `placedOut` innehåller (hem, 11 nov) och `now` är 05:00 samma dag, så ingen notis för den 11:e kommer. Utan bocken kommer den.
- `morgonReserv`: aktiviteten finns och har start 06:00 den 11:e. Reserven är `stockholm("2026-11-11T06:45")` med titeln `ReminderPlanner.fallbackTitle`.
- `reservensTak`: `fallbackDate(start: stockholm("2026-11-11T11:30"), timing: .sameMorning) == stockholm("2026-11-11T12:00")`. De fyra befintliga fallen skrivs om med `timing: .eveningBefore` och samma värden.
- `morgonRetainable`: med `now` 06:30 den 11:e finns identifieraren för (hem, 11 nov) i `retainable`. Med `now` 05:30 finns den inte.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter ReminderPlanner`
Förväntat: de nya testerna faller, eftersom tiden räknas kvällen före. Ett kompileringsfel kommer från `fallbackDate(start:timing:)`.

- [ ] **Steg 3: Byt de tre ställen som räknar `pickup.date.adding(days: -1)` mot `ReminderTime.date(forPickup:settings:)`**

Det gäller `plan`, `retainable` och `planLiveActivity`. Reserven får `timing: input.settings.timing`. Uppdatera dokumentationskommentaren vid taket: morgontiden stannar vid 09:00, så starten ligger aldrig efter 12:00.

- [ ] **Steg 4: Kör testerna**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter ReminderPlanner`
Förväntat: alla gröna. Live Activity-testen för morgonen kommer i Uppgift 3.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: Planeraren räknar påminnelsen för samma morgon"
```

---

### Uppgift 3: Live Activity med samma morgon

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderPlanner.swift` (`planLiveActivity`)
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/PickupActivityTexts.swift`, bara kommentaren på rad 28 om att aktiviteten "bara lever kvällen före"
- Test: `ReminderPlannerTests.swift`, `LiveActivityDiffTests.swift`

**Gränssnitt:**
- Använder: `ReminderTime.date(forPickup:settings:)`.
- Skapar: `static let morningActivityCutoffMinutes = 720` i `ReminderPlanner`, för "före 12:00".

Regeln för vilken tömning som gäller:
- **Kvällen före:** som i dag. Det är första tömningen efter i dag som inte är utställd, och `startsImmediately` gäller när tömningen är i morgon och starten har passerat.
- **Samma morgon:** det är första tömningen som inte är utställd och som antingen är efter i dag, eller är i dag med klockan före 12:00. `startsImmediately` gäller när tömningen är i dag och `now >= start`.

- [ ] **Steg 1: Skriv testerna som ska falla**

- `morgonAktivitetIDagFöreTolv`: `now` är 07:30 den 11:e, med tömning 11 och 18 nov. Aktiviteten gäller den 11:e, med `start == stockholm("2026-11-11T06:00")` och `startsImmediately == true`.
- `morgonAktivitetIDagEfterTolv`: `now` är 12:00 den 11:e. Aktiviteten gäller den 18:e, med start 06:00 den 18:e och `startsImmediately == false`.
- `morgonAktivitetKvällenFöreSchemaläggs`: `now` är 20:00 den 10:e. Aktiviteten gäller den 11:e med start 06:00 och `startsImmediately == false`.
- `morgonUtställdIDag`: `placedOut` innehåller (hem, 11 nov) och `now` är 07:30. Aktiviteten gäller den 18:e.
- I `LiveActivityDiffTests`, `bytTillMorgonErsätterVäntande`: en väntande aktivitet för den 11:e med start 18:00 den 10:e, och önskad aktivitet med start 06:00 den 11:e. Resultatet är `[.remove(id), .start(desired)]`. Testet ska gå igenom direkt, eftersom det skyddar regeln i Granskningsfokus 1. Skriv det ändå, och notera att det var grönt från början.
- `pågåendeIDagLeverEfterTolv`: en pågående aktivitet för i dag på huvudadressen behålls av `LiveActivityDiff.actions` när önskad aktivitet gäller den 18:e. Även det gäller redan i dag.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "ReminderPlanner|LiveActivityDiff"`
Förväntat: de fyra planerartesterna faller, eftersom tömningen i dag aldrig väljs. De två diff-testerna går igenom.

- [ ] **Steg 3: Ändra urvalet och `startsImmediately` i `planLiveActivity` enligt regeln ovan**

- [ ] **Steg 4: Kör hela paketet**

Kör: `cd iOS/Packages/SophamtningKit && swift test`
Förväntat: alla gröna.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: Live Activity samma morgon som tömningen"
```

---

### Uppgift 4: Texterna följer valet

**Filer:**
- Skapa: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Reminders/ReminderTimingTexts.swift`
- Ändra: `.../Home/HomeContent.swift`, `.../Home/AddressDetail.swift` och `.../App/AppModel.swift` (`missedReminderApplies`, `missedReminderText`)
- Test: `HomeContentTests.swift`, `AddressDetailTests.swift`, `AppModelRemindersTests.swift`, `ReminderTimingTextsTests.swift` (ny)

**Gränssnitt:**
- Skapar, i en `extension ReminderTiming`:
  - `toggleTitle: String` ger "Påminn mig kvällen före" eller "Påminn mig samma morgon".
  - `actionTitle(isOn: Bool) -> String` ger "Slå på påminnelse kvällen före", "Stäng av påminnelse samma morgon" och så vidare.
  - `title: String` ger "Kvällen före" eller "Samma morgon".
  - `settingsValue(minutes: Int) -> String` ger "Kvällen före, 18:00".
  - `settingsFooter: String` ger de två texterna under listan, ordagrant från specen.
  - `missedText: String` ger "Tömning i morgon. Påminnelsen för i kväll har redan passerat." eller "Tömning i dag. Påminnelsen för i morse har redan passerat."
- Ändrar:
  - `HomeContent.reminderTitle` och `HomeContent.reminderActionTitle(isOn:)` från #50 tar `timing: ReminderTiming` och använder texterna ovan. Alla anrop i appen (huvudkortet, `AddressView` och `AddressQuickActions`) skickar `model.settings.timing`.
  - `AddressDetail.missedReminder(events:settings:now:)` gäller tömningen `ReminderTime.pickupDay(remindedOn: today, timing:)`.
  - `AppModel.missedReminderApplies(to:)` använder samma dag i stället för `today.adding(days: 1)`.

Texterna som räknar en dag använder `ReminderTime.reminderDay(forPickup:timing:)` i stället för `event.date.adding(days: -1)`, och `settings.activeMinutes` i stället för `settings.reminderMinutes`:
- `AddressDetail.reminderText`, kväll: oförändrad. Morgon: "Onsdag kl. 06:00, samma dag som tömningen." När ingen kommande tömning finns, i stället för "Kvällen före varje tömning kl. 18:00.": "Samma morgon som varje tömning kl. 06:00."
- `AddressDetail.reserveText`: kvällen oförändrad. Morgon: "Onsdag kl. 06:45, samma dag som tömningen, om aktiviteten inte syns." Funktionen tar `timing`.
- `AddressDetail.liveActivityText`: "Visas på låsskärmen från kl. 06:00 samma morgon. …". Resten av meningen är densamma som i dag.
- `HomeContent.reminderText`: "Påminnelse onsdag kl. 06:00" räknas från påminnelsedagen. Texten när påminnelsen är av blir `settings.timing.toggleTitle`.

- [ ] **Steg 1: Skriv testerna som ska falla**

```swift
@Test func reglagetsNamn() {
    #expect(ReminderTiming.sameMorning.toggleTitle == "Påminn mig samma morgon")
    #expect(ReminderTiming.sameMorning.actionTitle(isOn: true) == "Stäng av påminnelse samma morgon")
    #expect(ReminderTiming.eveningBefore.actionTitle(isOn: false) == "Slå på påminnelse kvällen före")
    #expect(ReminderTiming.sameMorning.settingsValue(minutes: 360) == "Samma morgon, 06:00")
}
```

I `AddressDetailTests`, med tömning onsdag 2026-11-11 och morgonval 06:00:
- `reminderText` ger "Onsdag kl. 06:00, samma dag som tömningen." när `now` är tisdag 20:00.
- Med `now` onsdag 07:00 och nästa tömning den 18:e: "Onsdag kl. 06:00, samma dag som tömningen." för den 18:e. Det är Granskningsfokus 3.
- `missedReminder` ger "Tömning i dag. Påminnelsen för i morse har redan passerat." med `now` onsdag 07:00, och `nil` med `now` onsdag 05:00.
- `reserveText(stockholm("2026-11-11T06:45"), timing: .sameMorning)` ger "Onsdag kl. 06:45, samma dag som tömningen, om aktiviteten inte syns."
- `liveActivityText` börjar med "Visas på låsskärmen från kl. 06:00 samma morgon."

I `HomeContentTests`: "Påminnelse onsdag kl. 06:00" med morgonval och `now` tisdag 20:00, och "Påminn mig samma morgon" när påminnelsen är av.

I `AppModelRemindersTests`: `missedReminderText` gäller dagens tömning med morgonval, och `nil` när tömningen i dag är utställd.

Befintliga tester för kvällen ska gå igenom oförändrade, utom där anropet behöver `timing:`.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter "ReminderTimingTexts|AddressDetail|HomeContent|AppModelReminders"`
Förväntat: kompileringsfel, och därefter fel på de nya morgontexterna.

- [ ] **Steg 3: Lägg till texterna och byt anropen**

- [ ] **Steg 4: Kör hela paketet**

Kör: `cd iOS/Packages/SophamtningKit && swift test`
Förväntat: alla gröna.

- [ ] **Steg 5: Committa**

```bash
git commit -am "feat: Texterna om påminnelsen följer valet"
```

---

### Uppgift 5: Inställningen och `AppModel`

**Filer:**
- Ändra: `iOS/Packages/SophamtningKit/Sources/SophamtningKit/App/AppModel.swift`
- Ändra: `iOS/Sophamtning/Views/SettingsView.swift`
- Ändra: `iOS/SophamtningUITests/AccessibilityAuditTests.swift:100`, eftersom radens namn blir "Påminnelse"
- Test: `AppModelRemindersTests.swift`, `AppModelLiveActivityTests.swift`

**Gränssnitt:**
- Skapar: `AppModel.setReminderTiming(_ timing: ReminderTiming) -> Bool` (`@discardableResult`). Den sparar valet, kör `applyReminders()` och returnerar `false` vid lagringsfel. Då är allt som förut.
- Ändrar: `AppModel.setReminderMinutes(_:)` kontrollerar mot `settings.timing` och skriver till `reminderMinutes` eller `morningMinutes`.

- [ ] **Steg 1: Skriv testerna som ska falla**

- `bytTillMorgonFlyttarNotisen`: en adress har notiser på och tömning den 11:e, och `now` är tisdag 12:00. Efter `setReminderTiming(.sameMorning)` har schemaläggaren en notis kl. 06:00 den 11:e och ingen kl. 18:00 den 10:e.
- `bytTillbakaGerFörraTiden`: `setReminderMinutes(1200)`, sedan `setReminderTiming(.sameMorning)`, `setReminderMinutes(420)` och `setReminderTiming(.eveningBefore)`. Resultatet är `settings.activeMinutes == 1200` och `settings.morningMinutes == 420`.
- `morgontidAvvisasPåKvällen`: med `.eveningBefore` ger `setReminderMinutes(360)` `false`, och inget ändras.
- `bytAvValSchemaläggerInteAvstängt`: med notiser och Live Activity av ger bytet inga notiser och ingen aktivitet.
- `lagringsfelVidBytBehållerValet`: när lagringen kastar ger `setReminderTiming` `false`, och `settings.timing` är oförändrat.
- I `AppModelLiveActivityTests`, `bytTillMorgonErsätterVäntandeAktivitet`: en väntande aktivitet för kvällen före tas bort, och en med start 06:00 startas.

- [ ] **Steg 2: Kör och se dem falla**

Kör: `cd iOS/Packages/SophamtningKit && swift test --filter AppModel`
Förväntat: kompileringsfel, eftersom `setReminderTiming` saknas.

- [ ] **Steg 3: Lägg till `setReminderTiming` och ändra `setReminderMinutes`**

- [ ] **Steg 4: Inställningssidan i `SettingsView.swift`**

- Raden heter "Påminnelse", med värdet `settings.timing.settingsValue(minutes: settings.activeMinutes)`. Texten under delen blir `settings.timing.settingsFooter`.
- Sidan får titeln "Påminnelse" och två `ResultList` med rubrikerna "När" och "Tid".
  - **När** har `ChoiceRow` för `ReminderTiming.allCases`, med `title` och `setReminderTiming`.
  - **Tid** har `ChoiceRow` för `settings.timing.times`, med valt värde `settings.activeMinutes` och `setReminderMinutes`.
- Felmeddelandet och `clearStorageError()` fungerar som i dag.
- Uppdatera `AccessibilityAuditTests.swift:100` så att den letar efter "Påminnelse".

- [ ] **Steg 5: Kör paketet och bygg appen**

Kör: `cd iOS/Packages/SophamtningKit && swift test`
Förväntat: alla gröna.

Kör: `xcodebuild -project iOS/Sophamtning.xcodeproj -scheme Sophamtning -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Förväntat: `** BUILD SUCCEEDED **`.

- [ ] **Steg 6: Kontrollera i simulatorn**

Öppna Inställningar > Påminnelse och växla mellan valen. Ta skärmbilder i ljust och mörkt läge och vid AX5. Kontrollera att tiderna byts, att bocken följer med och att texten under listan följer valet. Kontrollera också att huvudkortets reglage heter "Påminn mig samma morgon".

- [ ] **Steg 7: Committa**

```bash
git commit -am "feat: Välj kvällen före eller samma morgon i inställningarna"
```

---

### Uppgift 6: Verifiering före PR

- [ ] Kör det berörda UI-testet `-only-testing:SophamtningUITests/CoreFlowTests/testPaminnelserArAvstangdaFranBorjan`. Det letar efter reglagets namn och ska gå igenom med kvällsvalet som förval.
- [ ] Kör hela UI-sviten en gång, och schemat `Granskning`, innan PR:en görs redo.
- [ ] Driftsätt på Jespers iPhone och be honom prova att byta till samma morgon.
- [ ] Skapa PR:en `feat: Påminnelse på morgonen`, med beskrivningen på svenska.
