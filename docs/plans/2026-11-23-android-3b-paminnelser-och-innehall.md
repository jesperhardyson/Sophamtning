# Android 3b: Påminnelser, hemskärmen, adressvyn, widgeten och Utställt

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** `Android/core` får resten av logiken från `SophamtningKit`, alltså det som skärmarna i plan 4 och påminnelserna i plan 5 behöver: påminnelseplaneraren och texterna, Utställt, hemskärmens och adressvyns innehåll, och widgetens innehåll. Allt är ren Kotlin, och testerna från iOS skrivs om.

**Arkitektur:** samma som i 3a. Varje uppgift skriver om en grupp Swift-filer till ett paket under `se.hardyson.sophamtning.core`, tillsammans med testfilerna för gruppen. iOS-koden i `main` är facit. Hushållet tas bort, och på Android gäller reglerna för en adress som inte delas (specen, avsnittet Ställ ut utan hushåll).

**Teknik:** Kotlin, `java.time`, kotlin.test och coroutines.

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnitten Med i första versionen, Påminnelser och Widgetar och snabbinställningar.

## Gemensamma krav

- Samma regler som i plan 3a, avsnittet Gemensamma krav: hur en Swift-fil skrivs om, hur testerna skrivs om, vad som utgår på Android, tid i Stockholm och commit-typerna `build:` och `test:`.
- **Hushållet** utgår. Där iOS-koden tar `isShared`, deltagare eller bockar från andra ger Android alltid samma svar som för en adress som inte delas, och parametrarna tas bort. Texter som bara gäller delning ("Delas med …", "av {namn}", "skickas när nätet finns") tas bort. Raden **Utställt** har undertexten **av dig · kl. {hh:mm}**, och raderna på hemskärmen **Kärlen är utställda**.
- **Live Activity heter Live Update** i alla texter som visas på Android, till exempel "Live Update söndag kl. 17:30" och "Notis och Live Update söndag kl. 18:00". Namnen i koden behåller iOS-ordet (`liveActivity…`), så att de går att jämföra med iOS. Testerna har Android-texterna.
- **Systemets namn:** där en text nämner iOS säger Android-texten systemet, till exempel "Notiser är avstängda för appen" i stället för "Notiser är avstängda i iOS".
- **Ikoner:** SF Symbols-namn följer inte med. Där iOS-innehållet bär ett ikonnamn bär Android-innehållet en `enum` eller ingenting, och ikonen väljs i plan 4.

## Granskningsfokus

1. **Sommartid och vintertid.** En påminnelse kl. 18:00 kvällen före en tömning måndagen efter omställningen hamnar en timme fel. Förväntat: klockslaget gäller i Stockholm, också omställningshelgen (`ReminderPlannerTests`, `ReminderTimeTests`, med `TZ=America/New_York`).
2. **Utställt för en tömning som redan passerat, eller samma dag efter påminnelsen.** Förväntat: samma regler som iOS för när knappen visas och när bocken rensas (`PlacedOutContentTests`, `HomeContentTests`).
3. **Två påminnelser samma dag**, kvällen före och samma morgon, och Live Update vid samma tid som en av notiserna. Förväntat: notisen ersätts av Live Update bara när tiderna är lika, och texterna på huvudkortet blir som på iOS (`ReminderTimingTextsTests`).
4. **Okänd fraktion, uppskattat datum eller avvikelse** på hemskärmen, i adressvyn och i widgeten. Förväntat: färg, ikon och text alltid, och "ca" för `estimated`.
5. **En adress utan schema, med ett fel eller med ett utgånget schema.** Förväntat: samma lägen som iOS, och ett tekniskt fel visas aldrig som att adressen saknas (`HomeContentTests`, `AddressDetailTests`, `WidgetContentTests`).

---

### Uppgift 1: Påminnelseplaneraren

**Filer:**
- Skriv om: `Reminders/ReminderTime.swift`, `ReminderPlanner.swift`, `NotificationDiff.swift`, `PickupActivityTexts.swift`, och de delar av `PickupActivityAttributes.swift` som planeraren använder (`PickupActivityContent`, `ActivityFraction`), utan ActivityKit.
- Till: `.../core/reminders/`
- Test: `ReminderTimeTests`, `ReminderPlannerTests`, `NotificationDiffTests`, `LiveActivityTimeTests`

**Gränssnitt:**
- Tar: `ReminderSettings`, `ReminderTiming`, `SavedAddress`, `CachedSchedule`, `PlacedOut`, `ScheduleLogic` och `StockholmClock`.
- Ger: `PlannerAddress`, `PlannerInput`, `PlannedNotification` (med `identifier(key, date, timing)` exakt som iOS), `PlannedLiveActivity`, `ReminderPlan`, `ReminderPlanner.plan(input)` och `retainable(input)`, och `NotificationDiff`. Planen säger vad som ska finnas. Hur det blir alarm och notiser på Android bestäms i plan 5.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** `cd Android && ./gradlew :core:test` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: gröna båda gångerna.
- [ ] **Steg 4: Commit** `build: påminnelseplaneraren i Android-kärnan`

### Uppgift 2: Texterna för påminnelser och Utställt

**Filer:**
- Skriv om: `Reminders/ReminderTimingTexts.swift`, `ReminderSettingsTexts.swift`, `PlacedOutNotification.swift`, `PlacedOutAction.swift`, och de delar av `Household/HouseholdLogic.swift` och `HouseholdLine.swift` som gäller en adress som inte delas (`showsPlaceOutButton`, `currentMark` och raden Utställt)
- Till: `.../core/reminders/` och `.../core/placedout/`
- Test: `ReminderTimingTextsTests`, `PlacedOutNotificationTests`, `PlacedOutContentTests`, testerna för `PlacedOutAction` som flyttades hit från 3a (`PlacedOutTests.swift`: `utstalltAvslutarAktiviteten…` och `utställtTarBortBåda`), `textenUnderReglaget` från `SourceMessagesTests`, och de fall i `HouseholdLogicTests` som inte gäller delning

**Gränssnitt:**
- Ger: texterna med Android-orden (se Gemensamma krav), och `PlacedOutAction.perform(store, entry, today, end, cancelReminder)` med samma ordning och felhantering som iOS: avsluta Live Update, spara bocken och ta bort båda notiserna, också när ett steg misslyckas.

- [ ] **Steg 1: Skriv om testerna**, med Android-texterna, och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** som i uppgift 1. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: texter för påminnelser och Utställt i Android-kärnan`

### Uppgift 3: Hemskärmens innehåll

**Filer:**
- Skriv om: `Home/HomeContent.swift` och `Home/AddressAction.swift`
- Till: `.../core/home/`
- Test: `HomeContentTests` och `AddressActionTests`

**Gränssnitt:**
- Tar: planeraren och texterna från uppgift 1 och 2, `ScheduleEnding`, `SourceMessages` och `ScheduleLogic`.
- Ger: samma innehållstyper som iOS, alltså huvudkortet, raderna under Fler adresser, förslaget om påminnelse och felrutorna, som oföränderliga `data class` som skärmarna i plan 4 ritar.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: hemskärmens innehåll i Android-kärnan`

### Uppgift 4: Adressvyn och widgeten

**Filer:**
- Skriv om: `Home/AddressDetail.swift`, `Schedule/WidgetContent.swift`, och `CalendarLink` i `Schedule/LockScreenContent.swift`. `LockScreenContent` själv utgår.
- Till: `.../core/home/AddressDetail.kt`, `.../core/widget/WidgetContent.kt` och `.../core/kommun/SourceLink.kt` (`calendar(url)`)
- Test: `AddressDetailTests`, `WidgetContentTests`, `adressvynHarRutanFranSparatSchema` från `OtherDaysNoteTests`, och de tester för `CalendarLink` som finns i `LockScreenContentTests` eller `WebLinkTests`

**Gränssnitt:**
- Ger: adressvyns innehåll som oföränderliga typer, och `WidgetContent.make(...)` med samma lägen som iOS. `CalendarLink` får på Android en funktion `googleCalendar(ics: String): String?` som ger `https://calendar.google.com/calendar/render?cid=<webcal-adressen kodad>`, enligt specen, avsnittet Kalender. Den har ett eget test med en adress som innehåller `%` och å.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: adressvyn och widgetens innehåll i Android-kärnan`

### Uppgift 5: PR

- [ ] **Steg 1:** Kör hela sviten: `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: gröna.
- [ ] **Steg 2:** PR med titeln `build: Påminnelser, hemskärm, adressvy och widget i Android-kärnan`, med PR-mallens rubriker. Beskrivningen räknar upp de iOS-tester som inte skrivits om, och varför.

## Inte med i 3b

- `LiveActivityDiff` och `AppModelLiveActivityTests`: hur Live Updates startas och avslutas på Android (alarm och pågående notis) skiljer sig från ActivityKit, och bestäms i plan 5.
- `AppModel` och dess tester: appens tillstånd blir ViewModels i plan 4.
- `SiriAnswers`, hushållets synk och modeller, `LockScreenContent` och allt i `SophamtningDesign`.
