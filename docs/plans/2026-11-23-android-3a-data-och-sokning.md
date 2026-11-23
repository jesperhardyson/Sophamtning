# Android 3a: Lagring, schema, sökning, kommun och meddelanden

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** `Android/core` får logiken för data och sökning från `SophamtningKit`: lagringen, schemalogiken, sökningen och områdena, kommunkollen, Nyheter och källmeddelandena. Allt är ren Kotlin och har testerna från iOS omskrivna.

**Arkitektur:** Varje uppgift skriver om en grupp Swift-filer i `SophamtningKit` till ett paket under `se.hardyson.sophamtning.core`, tillsammans med testfilerna för gruppen. iOS-koden i `main` är facit för beteende, namn och texter. Lagringen skriver samma JSON-filer i samma format som iOS, i en katalog som appen anger.

**Teknik:** Kotlin, kotlinx.serialization, kotlinx.coroutines, `java.time`, `java.nio.file` och kotlin.test.

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnitten Med i första versionen och Arkitektur.

## Planerna för Android

Plan 3 i `2026-11-23-android-1-release-och-ci.md` delas i två, eftersom logiken i iOS är omkring 5 000 rader med 700 tester:

- **3a (den här):** lagring, schema, sökning och områden, kommunkoll, Nyheter och källmeddelanden.
- **3b:** påminnelseplaneraren och texterna för påminnelser och Live Update, hemskärmens innehåll, adressvyn, widgetens innehåll och Utställt.

Plan 4 och framåt följer listan i plan 1.

## Gemensamma krav

- **Hur en Swift-fil skrivs om:**
  - `enum` med bara statiska funktioner blir `object`.
  - `struct` blir `data class`, och `enum` med fall blir `enum class` eller `sealed interface`.
  - `Date` blir `java.time.Instant`, `TimeInterval` blir `java.time.Duration`, och `URL` blir `String`, som i plan 2.
  - Publika namn behåller iOS-namnen i Kotlin-form (`days(until:)` blir `daysUntil`).
  - Kommentarerna skrivs om på svenska, och alla texter som visas är tecken för tecken desamma som i iOS.
- **Testerna:** varje `@Test` i de namngivna iOS-testfilerna skrivs om med samma namn och värden. Parametriserade tester (`arguments:`) blir en loop i ett test, och felmeddelandet innehåller fallet. Ett test som bara prövar något som utgår på Android (se nästa punkt) tas bort, och det skrivs en rad i ledgern om varför.
- **Det som utgår på Android:** allt som rör hushåll och CloudKit, ActivityKit, Siri, widgetar på låsskärmen och `#if os(iOS)`. Det tas bort, och ett fält som bara finns för det utelämnas. Data som sparas innehåller ändå samma JSON-nycklar som iOS skriver, så att formatet blir detsamma.
- **Sparade svar** läses med `ApiDecoding` och aldrig med `Json.decodeFromString`, så att samma förlåtande regler gäller som för nya svar (beslut i plan 2).
- **Tid:** "i dag" räknas i `Europe/Stockholm` med `StockholmClock`. Tester som rör tid körs också med `TZ=America/New_York`.
- Commits är `build:` eller `test:`, eftersom Android inte släpps ännu.

## Granskningsfokus

1. **En fil som inte går att läsa** (skadad, halvskriven eller från en framtida version) ger tomma adresser och skrivs sedan över. Förväntat: `StoreRead.Unreadable` som på iOS, och ingen skrivning över den, så att `moveAside` kan spara den (`LocalStoreTests`).
2. **En skrivning avbryts mitt i**, till exempel för att appen dödas. Förväntat: den gamla filen är hel, eftersom skrivningen sker till en temporär fil som sedan flyttas atomiskt.
3. **Två sökningar i snabb följd**, där svaret på den första kommer sist. Förväntat: bara den senaste sökningen visas (`LatestOnlyTests`, `SearchStateTests`).
4. **En ort med samma namn i flera kommuner, eller med versaler, bindestreck eller å, ä och ö** i kommunkollen. Förväntat: samma svar som iOS (`KommunCheckerTests`).
5. **Dagen byts medan ett meddelande eller ett schema är sparat.** Förväntat: utgångna meddelanden och tömningar visas inte, räknat i Stockholm (`SourceMessagesTests`, `ScheduleLogicTests`).

---

### Uppgift 1: Lagringen

**Filer:**
- Skriv om: `Storage/StoredModels.swift`, `Storage/LocalStore.swift`, `Storage/AddressList.swift`
- Till: `Android/core/src/main/kotlin/se/hardyson/sophamtning/core/storage/StoredModels.kt`, `LocalStore.kt`, `AddressList.kt`
- Test: `LocalStoreTests.swift`, `AddressListTests.swift`, `PlacedOutTests.swift` och `sparatSchemaFranForeFaltetGarAttLasa` i `SourceMessagesTests.swift`, skrivna om till `.../core/storage/`

**Gränssnitt:**
- Tar: `ApiDecoding`, `AddressResponse`, `DayDate` och `StockholmClock` från plan 2.
- Ger: `AddressKey`, `SavedAddress`, `ReminderTiming`, `ReminderSettings` (med `sourceMessagesOn`), `CachedSchedule`, `PlacedOut` och `CachedSources`, med samma fält och JSON-nycklar som iOS. Vidare `sealed interface StoreRead<out T>` med `Missing`, `Value(value)`, `Unavailable` och `Unreadable`, och `class LocalStore(directory: java.io.File)` med samma metoder som iOS, utom de för hushåll. Uppgift 5 lägger till metoderna för minnet av källmeddelanden.
- Filnamnen är desamma som på iOS. Schemats filnamn byggs med samma hash av källa och id, så att samma adress ger samma fil.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera med kompileringsfel (`./gradlew :core:test`).
- [ ] **Steg 2: Implementera.** Skrivningen sker till en temporär fil i samma katalog, som sedan flyttas med `Files.move(…, ATOMIC_MOVE, REPLACE_EXISTING)`. Läsningen skiljer på att filen saknas (`Missing`), att den inte går att läsa (`Unavailable`, till exempel vid fel behörighet) och att innehållet är trasigt (`Unreadable`), som på iOS. `CachedSchedule.response` läses med `ApiDecoding.addressResponse`.
- [ ] **Steg 3: Ett test för avbruten skrivning**, `avbrutenSkrivningLamnarGamlaFilenHel`: skriv adresserna, låt nästa skrivning kasta ett fel efter att den temporära filen skapats (genom en injicerbar skrivfunktion), och kontrollera att `addressesState()` ger de första adresserna.
- [ ] **Steg 4: Kör** `cd Android && ./gradlew :core:test` och samma sak med `TZ=America/New_York … --rerun`. Förväntat: gröna båda gångerna.
- [ ] **Steg 5: Commit** `build: lagringen i Android-kärnan`

### Uppgift 2: Schemat

**Filer:**
- Skriv om: `Schedule/ScheduleLogic.swift`, `ScheduleEnding.swift`, `RefreshPolicy.swift`, `OtherDaysNote.swift`, `LatestOnly.swift`, `ScheduleRefresher.swift`
- Till: `.../core/schedule/`
- Test: `ScheduleLogicTests`, `ScheduleEndingTests`, `RefreshPolicyTests`, `OtherDaysNoteTests`, `LatestOnlyTests`, `ScheduleRefresherTests`
- Ändra: `.../core/dates/StockholmClock.kt` (rullar över)

**Gränssnitt:**
- Tar: `LocalStore`, `CachedSchedule` och `SoporApi`.
- Ger: samma funktioner som iOS. `LatestOnly` byggs med coroutines (`Job` och avbrott) i stället för `Task`. `ScheduleRefresher` tar `SoporApi`, `LocalStore` och en klocka (`() -> Instant`).

- [ ] **Steg 1: Skriv om testerna**, och lägg till `dateOnRullarOverTillNastaDag`: `StockholmClock.dateOn(day("2026-11-08"), minutes = 1440 + 360)` är `2026-11-09T05:00:00Z`, och `minutes = -60` ger `2026-11-07T22:00:00Z`, som `Calendar.date(from:)` på iOS. Se dem fallera.
- [ ] **Steg 2: Implementera.** `dateOn` räknar med `atStartOfDay(zone).plusMinutes` på väggklockan, med dagarna lagda till först (`plusDays(minutes.floorDiv(1440))`, och sedan `floorMod` för klockslaget), så att omställningsdagar blir rätt. Det rättar den mindre anmärkningen i plan 2.
- [ ] **Steg 3: Kör** som i uppgift 1. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: schemalogiken i Android-kärnan`

### Uppgift 3: Sökningen och områdena

**Filer:**
- Skriv om: `Schedule/AddressSearch.swift`, `SearchState.swift`, `AreaFilter.swift`, `AreaFinder.swift`, `AreaFinderState.swift`, `AreaContent.swift`, `AreaPickerContent.swift`
- Till: `.../core/search/`
- Test: `AddressSearchTests`, `SearchStateTests`, `AreaFilterTests`, `AreaFinderTests`, `AreaFinderStateTests` (om den finns), `AreaContentTests`, `AreaPickerContentTests`

**Gränssnitt:**
- Tar: `SoporApi`, `LatestOnly` och `DayDate`.
- Ger: samma typer och funktioner som iOS. Tillstånden som UI:t läser (`SearchState`, `AreaFinderState`) är oföränderliga `data class`, så att plan 4 kan lägga dem i ett `StateFlow`.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: sökning och områden i Android-kärnan`

### Uppgift 4: Kommunkollen och källorna

**Filer:**
- Skriv om: `Kommun/PlaceIndex.swift`, `KommunName.swift`, `KommunChecker.swift`, `App/SourceLink.swift`, `App/WebLink.swift`, och `Source.kommunerText` i `APIModels.swift`
- Till: `.../core/kommun/` och `.../core/api/` (för `kommunerText`)
- Ändra: `Android/core/build.gradle.kts`, så att ortlistan läses från `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Kommun/Resources/` som resurs i `main`
- Test: `KommunCheckerTests`, `SourceListTests`, `SourceContactTests`, `WebLinkTests`

**Gränssnitt:**
- Ger: `PlaceIndex.load(): PlaceIndex`, som läser `orter.json` från klassvägen en gång, och `KommunChecker` med samma svar som iOS. Vidare `Source.kommunerText` och funktionerna i `SourceLink` och `WebLink`. `WebLink` godtar bara `https`.

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.** Ortlistan kopieras inte. Kommentaren i `build.gradle.kts` säger att den delas med iOS. Normaliseringen av söktext (versaler, bindestreck, å, ä och ö) använder `Locale.ROOT` och samma regler som `KommunName.swift`.
- [ ] **Steg 3: Kör.** Förväntat: gröna. Appen byggs också (`./gradlew :app:assembleDebug`), för att se att resursen kommer med i APK:n.
- [ ] **Steg 4: Commit** `build: kommunkollen och källorna i Android-kärnan`

### Uppgift 5: Nyheter och källmeddelanden

**Filer:**
- Skriv om: `About/Changelog.swift` och `Messages/SourceMessages.swift`
- Till: `.../core/about/Changelog.kt` och `.../core/messages/SourceMessages.kt`
- Ändra: `LocalStore.kt` (`sourceMessageMemoryState()` och `setSourceMessageMemory(_)` för `source-messages.json`)
- Test: `ChangelogTests` och resten av `SourceMessagesTests`

**Gränssnitt:**
- Ger:
  - `Changelog.parse(markdown, hiding)`, med `hiddenVersions` tom på Android, eftersom version 1.0.0 av Android-appen ska visas.
  - `SourceMessages.active`, `SourceMessages.unseen` och `SourceMessages.notificationId`. Identifieraren `kalla.<källa>.<id>` blir ett heltals-id för Android-notiser genom en stabil hash, som specas i plan 5.
  - `SourceMessageKey`, `ActiveSourceMessage` och `SourceMessageMemory`, med samma JSON som iOS.

- [ ] **Steg 1: Skriv om testerna.** `riktigaChangelogenGårAttLäsa` läser `iOS/CHANGELOG.md` tills Android har en egen changelog, och en kommentar säger det. Se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** som i uppgift 1. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: Nyheter och källmeddelanden i Android-kärnan`

### Uppgift 6: PR

- [ ] **Steg 1:** Rätta raden om ortlistan i `CLAUDE.md`, så att den stämmer nu när Android läser den.
- [ ] **Steg 2:** Kör hela sviten: `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: gröna, och antalet tester står i PR:en.
- [ ] **Steg 3:** PR med titeln `build: Lagring, schema, sökning och kommunkoll i Android-kärnan`, med PR-mallens rubriker. Beskrivningen räknar upp de iOS-tester som tagits bort, och varför.
