# Android 4a: Appens tillstånd och de första skärmarna

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** Android-appen går att använda på riktigt. Man kan se om kommunen finns, söka och spara en adress eller ett område, och se hemskärmen, adressvyn och hela schemat med riktiga data från Sopor API. Man kan också ställa ut kärlen och ångra, ta bort och byta namn på en adress, och stänga källmeddelanden.

**Arkitektur:**
- `AppModel` från iOS skrivs om till `core/app/AppModel.kt`, som ren Kotlin med `StateFlow` och ett gränssnitt för påminnelserna. Påminnelserna har en tom implementation tills plan 5.
- Appen har en `ViewModel` per skärm, som läser `AppModel` och innehållstyperna från plan 3 (`HomeContent`, `AddressDetail` med flera).
- Navigeringen görs med Navigation 3, och backstacken är en lista med `@Serializable`-nycklar.
- Skärmarna ritas i Compose med temat från plan 2 och följer iOS-appen som den ser ut i dag, eftersom Pencil inte går att använda (specen, avsnittet Design).

**Teknik:** Navigation 3 (`androidx.navigation3`, 1.2), Lifecycle ViewModel Compose (2.11), Material 3, AndroidX Browser (Custom Tabs, 1.10), Ktor med OkHttp-motorn, Robolectric och Compose-tester.

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnitten Med i första versionen, Grundbeslut och Design. Facit för beteende och texter är `iOS/Packages/SophamtningKit/Sources/SophamtningKit/App/AppModel.swift` och vyerna i `iOS/Sophamtning/Views/`.

## Planerna för Android

Plan 4 delas i två:
- **4a (den här):** appens tillstånd, startvyn, hemskärmen, Lägg till adress, adressvyn och hela schemat.
- **4b:** inställningarna, Nyheter, datakällorna, kärlet med pratbubblorna, snabbmenyerna och granskningen av tillgänglighet och största text.

## Gemensamma krav

- Samma regler som i plan 3a och 3b för hur iOS-koden skrivs om, Android-orden och commit-typerna (`build:`, `test:`).
- **Utseendet:** iOS-appens färger, typsnitt, kort, chips och avstånd, men med Androids mönster:
  - ett övre appfält (`TopAppBar`) med stor rubrik som krymper vid scroll och en bakåtpil,
  - systemets bakåtgest (prediktiv bakåt),
  - `ModalBottomSheet` eller helskärm där iOS har ark,
  - en meny (`DropdownMenu`) där iOS har `···`,
  - svep för att ta bort med `SwipeToDismissBox` och en bekräftelse.

  Kant-till-kant gäller överallt, med rätt marginaler mot statusfältet och gestfältet.
- **Texterna** i skärmarna kommer från innehållstyperna i `core`. Etiketter som bara finns i UI:t läggs i `res/values/strings.xml`, på svenska, med samma ordalydelse som i iOS-vyerna.
- **Tillgänglighet:** varje kort och rad har en beskrivning för TalkBack, som motsvarar `accessibilityLabel` på iOS. Rubriker markeras som `heading()`, och knappar är minst 48 × 48 dp. Texterna följer systemets textstorlek. Fraktioner har alltid färg, ikon och text.
- **Ikoner för fraktioner:** Material Symbols. Varje ikonnamn från API:t (till exempel `trash`, `leaf`, `wine`) mappas till en symbol i en tabell. Okänt namn ger återvinningssymbolen.
- **Webblänkar** öppnas med Custom Tabs, och bara `https` (`WebLink`).
- **Nätet:** `SoporClient(OkHttp.create(), BuildConfig.VERSION_NAME)`, skapad en gång i `Application`.
- **UI-tester** körs på JVM med Robolectric och ett `FakeSoporApi` som svarar med iOS-filerna i `iOS/Sophamtning/UITestData/`. Testerna läser dem direkt, som `core` gör med fixturerna.

## Granskningsfokus

1. **Appen startar utan nät, eller när källan svarar 502.** Förväntat: senast sparade schemat visas, och ett fel visas aldrig som att adressen saknas.
2. **Telefonen vrids, eller appen dödas och startas om mitt i en sökning eller på adressvyn.** Förväntat: backstacken och sökningen finns kvar (`rememberSaveable` och `SavedStateHandle`), och ingen dubbel hämtning görs.
3. **Största textstorleken (200 %) och ett smalt fönster.** Förväntat: inget klipps, rader bryts, och knappar går att nå.
4. **Ett adress-id med å, ä, ö och `%`** sparas, öppnas och tas bort. Förväntat: samma id hela vägen, och adressen hämtas med sin sparade `url`.
5. **Dagen byts medan appen är öppen**, till exempel vid midnatt. Förväntat: hemskärmen räknar om "i dag" och "i morgon" när appen kommer tillbaka i förgrunden, eller vid nästa minutbyte om den är öppen.

---

### Uppgift 1: Appens tillstånd i kärnan

**Filer:**
- Skriv om: `App/AppModel.swift` och `App/AppModel+SourceMessages.swift`, utom hushållet och påminnelsernas schemaläggning
- Till: `Android/core/src/main/kotlin/se/hardyson/sophamtning/core/app/AppModel.kt`, `AppModelSourceMessages.kt` och `ReminderScheduling.kt`
- Ändra: `core/storage/LocalStore.kt`, som får `placedOutTimes()` och `setPlacedOutTime(entry, at)` i den nya filen `placed-out-times.json` (`{ "<filnamn>-<iso>": <sekunder sedan 2001> }`). Det är bara på Android, och den rensas när bocken rensas.
- Test: `AppModelTests`, `AppModelSourceMessagesTests` och de 13 testerna i `SourceListTests` som väntade på `AppModel`, skrivna om till `core/app/`

**Gränssnitt:**
- Tar: hela `core`.
- Ger:
  - `class AppModel(api: SoporApi, store: LocalStore, reminders: ReminderScheduling, clock: () -> Instant, scope: CoroutineScope)` med `state: StateFlow<AppState>` (adresserna, scheman, inställningarna, lagringsfelet, Utställt med tider, och minnet av källmeddelanden) och samma funktioner som iOS för det som finns med:
    - adresser: `add`, `remove`, `rename`, `setPrimary` och `replace`,
    - hämtning och källor: `refreshAll(manual, context)` och `sourceList()`,
    - lagring: `retryStorage` och `startOver`,
    - Utställt: `markPlacedOut(key, date)` och `undoPlacedOut(key, date)`,
    - källmeddelanden: `dismissSourceMessage` och `setSourceMessages`,
    - påminnelser: `setNotifications(on, key)`, `dismissReminderOffer`, och inställningarnas setters.
  - `interface ReminderScheduling` med de anrop `AppModel` gör, och `NoReminders`, som inte gör någonting och används tills plan 5.
- Samtidiga hämtningar för samma adress serialiseras, som på iOS. `refreshAll` kontrollerar `ensureActive()` mellan adresserna (anmärkningen från 3a).

- [ ] **Steg 1: Skriv om testerna** och se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** `cd Android && ./gradlew :core:test` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: appens tillstånd i Android-kärnan`

### Uppgift 2: Appens skal, navigering och komponenter

**Filer:**
- Skapa:
  - `app/.../SophamtningApplication.kt`, som skapar `SoporClient`, `LocalStore(filesDir/Sophamtning)` och `AppModel` en gång,
  - `app/.../navigation/` med nycklarna `Home`, `AddAddress`, `KommunCheck`, `AreaPicker`, `AreaFinder`, `AreaConfirm`, `Address(key)` och `FullSchedule(key)`, och `NavDisplay`,
  - `app/.../ui/components/` med `FractionChip`, `ChipRow`, `CalendarTile`, `MessageCard`, `SectionCard`, `AddressPlaceLine` och `FractionIcons`.
- Ändra: `MainActivity.kt`, `AndroidManifest.xml` (`android:name` för `Application`) och `libs.versions.toml`
- Test: `app/src/test/.../ui/components/ComponentsTest.kt`

**Gränssnitt:**
- `FractionChip(info: FractionInfo, estimated: Boolean)` visar färg, ikon och hela namnet, som chipsen på iOS (`FractionViews.swift`), och bryts till nästa rad i `ChipRow` (`FlowRow`).
- `CalendarTile(day: DayDate)` visar månaden i versaler och dagens nummer, som `CalendarTile.swift`.
- `MessageCard(title, text, style, icon, link, onClose)` motsvarar `MessageCard.swift`.

- [ ] **Steg 1: Skriv testerna**:
  - `fraktionenVisasMedNamnOchIkon`: noden har texten "Pappersförpackningar" och en ikon med beskrivning.
  - `okandIkonGerAtervinning`: `FractionIcons.forName("okänd")` är återvinningssymbolen.
  - `kalenderbrickanVisarManadOchDag`: "NOV" och "9".
  - `meddelandekortetKanStangas`: knappen "Stäng meddelandet" anropar `onClose`.

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Lägg Navigation 3, Lifecycle och Browser i versionskatalogen med versionerna ovan, och Ktor OkHttp i `app`.
- [ ] **Steg 3: Kör** `./gradlew :app:testDebugUnitTest :app:lintDebug`. Förväntat: gröna och utan anmärkningar i lint.
- [ ] **Steg 4: Commit** `build: appens skal, navigering och komponenter på Android`

### Uppgift 3: Startvyn och Lägg till adress

**Filer:**
- Skriv om från iOS-vyerna: `StartIntroView.swift`, `SearchView.swift`, `KommunCheckView.swift`, `AreaPickerView.swift`, `AreaFinderSheet.swift` och `AreaConfirmSheet.swift`
- Till: `app/.../ui/start/`, `ui/search/`, `ui/kommun/` och `ui/area/`, med en `ViewModel` per flöde som håller `SearchState` och `AreaFinder` från `core`
- Test: `app/src/test/.../ui/AddAddressFlowTest.kt`

- [ ] **Steg 1: Skriv testerna**, med `FakeSoporApi` och `UITestData`:
  - `startvynVisarSokningOchKommunfragan`
  - `sokningVisarTraffarOchSparar`: skriv "Storgatan", tryck på första träffen, och hemskärmen visar adressen.
  - `kommunfraganSvararMedanManSkriver`: "Avesta" ger kommunens svar.
  - `omradeValjsOchBekraftas`: välj område, bekräfta, och hemskärmen visar området.
  - `ingenTraffVisarLankTillKommunfragan`

  Se dem fallera.
- [ ] **Steg 2: Implementera**, med samma texter och samma ordning som iOS.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: startvyn och Lägg till adress på Android`

### Uppgift 4: Hemskärmen

**Filer:**
- Skriv om från iOS-vyerna: `HomeView.swift`, `PrimaryCard.swift` och källmeddelandenas kort, utan kärlets animation och snabbmenyerna (4b)
- Till: `app/.../ui/home/`
- Test: `app/src/test/.../ui/HomeScreenTest.kt`

- [ ] **Steg 1: Skriv testerna**:
  - `huvudkortetVisarNastaTomningOchKarlen`
  - `stallUtOchAngra`: tryck **Ställ ut kärlen**, raden **Utställt** med "av dig · kl. …" visas, tryck **Ångra**, och knappen kommer tillbaka.
  - `svepTarBortMedBekraftelse`
  - `kallmeddelandetVisasOchStangs`: Avestas meddelande i `UITestData` ger kortet "Hämtrutterna läggs om", och det försvinner när man stänger det.
  - `felVidHamtningVisasInteSomSaknadAdress`: 502 från `FakeSoporApi` ger felrutan och det sparade schemat.
  - `dagbytetRaknasOm`: med en klocka som flyttas över midnatt ändras "i morgon" till "i dag".

  Se dem fallera.
- [ ] **Steg 2: Implementera.** Pull-to-refresh anropar `refreshAll(manual = true)`. Hemskärmen hämtar när appen kommer i förgrunden (`LifecycleResumeEffect`), och räknar om dagen varje minut medan den syns.
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: hemskärmen på Android`

### Uppgift 5: Adressvyn och hela schemat

**Filer:**
- Skriv om från iOS-vyerna: `AddressView.swift`, `ScheduleViews.swift` och `SourceCard.swift`, och kalenderavsnittet med Google Kalender
- Till: `app/.../ui/address/`
- Test: `app/src/test/.../ui/AddressScreenTest.kt`

- [ ] **Steg 1: Skriv testerna**:
  - `adressvynVisarNastaKommandeOchPerKarl`
  - `helaSchemaOppnasOchVisarAllaDatum`
  - `bytNamnOchTaBortFranMenyn`
  - `kalenderradenOppnarGoogleKalender`: intentet har `calendar.google.com` och `cid=`.
  - `kallkortetHarWebbplatsOchKommunensInformation`
  - `adressMedAaoOchProcentOppnasOchTasBort`

  Se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör.** Förväntat: gröna.
- [ ] **Steg 4: Commit** `build: adressvyn och hela schemat på Android`

### Uppgift 6: Prova i emulatorn och PR

- [ ] **Steg 1:** Kör hela sviten: `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` och `TZ=America/New_York ./gradlew :core:test --rerun`. Förväntat: gröna.
- [ ] **Steg 2:** Installera i emulatorn och ta skärmbilder i ljust och mörkt läge, och med största textstorleken:
  - startvyn,
  - sökningen med träffar,
  - kommunfrågan,
  - områdesvalet,
  - hemskärmen med en och flera adresser och Avestas meddelande,
  - adressvyn,
  - hela schemat.

  Skicka dem till Jesper.
- [ ] **Steg 3:** PR med titeln `build: De första skärmarna i Android-appen`, med PR-mallens rubriker och skärmbilderna.
