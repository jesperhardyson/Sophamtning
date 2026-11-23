# Android 2: Grunden

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** `Android/` finns som Gradle-projekt med modulerna `core` och `app`. `core` avkodar Sopor API v1 och anropar det med samma regler som iOS, och `app` startar och visar rubriken i appens typsnitt. CI testar Android, och Release Please känner till komponenten `android` utan att släppa något.

**Arkitektur:** `core` är en ren Kotlin/JVM-modul och motsvarar `SophamtningKit/API` och `Dates`. Testerna läser iOS-fixturerna direkt från `iOS/`. `app` är en Compose-app med ett tema, och typsnitten kopieras från iOS-paketet när appen byggs. `android.yml` följer mönstret i `ios.yml` med jobbet `changes`.

**Teknik:** AGP 9.5 med inbyggt Kotlin (Kotlin 2.4), Gradle med Kotlin DSL och versionskatalog, JDK 21 som toolchain, kotlinx.serialization, kotlinx.coroutines, Ktor-klienten (OkHttp-motorn i appen, `MockEngine` i testerna), Jetpack Compose (BOM) och Material 3. För testerna används JUnit 4 och Robolectric för Compose-testet på JVM.

**Spec:** `docs/specs/2026-11-23-android-app.md`. Avsnitten Grundbeslut, Arkitektur, Release och CI. iOS-koden i 1.3.1 är facit för avkodning och klient.

## Gemensamma krav

- Lägsta version Android 12 (`minSdk = 31`). `targetSdk` och `compileSdk` är senaste stabila API.
- `applicationId` och `namespace` för appen är `se.hardyson.sophamtning`. `core` har paketet `se.hardyson.sophamtning.core`.
- User-Agent `Sophamtning-Android/<version>`. Bas-URL `https://sopor.hardyson.se/api/v1`. Tidsgräns 15 sekunder.
- "I dag" räknas i `Europe/Stockholm`.
- Appen beror bara på AndroidX, Jetpack och JetBrains bibliotek. Testberoenden får också vara JUnit och Robolectric.
- Versionerna sätts i `Android/gradle/libs.versions.toml`. Välj senaste **stabila** version (inte alpha, beta eller RC) när uppgiften görs. AGP 9.5.0 och Kotlin 2.4.10 är stabila i dag. Gradle-versionen väljs ur AGP:s kompatibilitetstabell.
- Kommentarer och testnamn på svenska, som i iOS-koden.
- Commits i den här planen är `build:`, `ci:`, `test:` eller `docs:`, så att ingen Android-release skapas förrän appen är klar (plan 7).

## Granskningsfokus

1. **Ett adress-id med å, ä, ö eller `%`** byggs om eller kodas om när adressen hämtas. Förväntat: `url` från sökningen används oförändrad (`behallerUrlMedAaoOchProcent`).
2. **Ett okänt fält, en okänd fraktion eller ett trasigt meddelande** fäller hela svaret. Förväntat: samma förlåtande avkodning som `Lenient` på iOS (`avkodarAdressMedOkandaFalt`, `tolAndrasFraktionsId`, `ettTrasigtMeddelandeFallerInteDeAndra`).
3. **Nätfel och 502** visas som att adressen saknas. Förväntat: `Network` och `SourceUnavailable` skiljs från `NotFound` (`statuskoderMappas`, `natfelBlirNetwork`).
4. **Telefonen står i en annan tidszon** och dagen byts fel kring midnatt. Förväntat: dagen i Stockholm (`idagFoljerStockholmEfterMidnatt`, och CI kör `core`-testerna med `TZ=America/New_York`).
5. **En Android-PR** startar iOS-jobbet på macOS, eller blir hängande på `test`. Förväntat: `test` hoppas över och `android` körs.

---

### Uppgift 1: Gradle-projektet och verktygen

**Filer:**
- Skapa: `Android/settings.gradle.kts`, `Android/build.gradle.kts`, `Android/gradle.properties`, `Android/gradle/libs.versions.toml`, Gradle-wrappern (`Android/gradlew`, `Android/gradlew.bat`, `Android/gradle/wrapper/*`), `Android/version.txt`, `Android/.gitignore`
- Skapa: `Android/core/build.gradle.kts`, `Android/core/src/test/kotlin/se/hardyson/sophamtning/core/SmokeTest.kt`

**Gränssnitt:**
- Ger: modulerna `:core` (Kotlin JVM, toolchain 21) och `:app` (läggs till i uppgift 4). `Android/version.txt` med `0.0.0`, som `app` läser som `versionName`.

- [ ] **Steg 1: JDK 21 lokalt**

Kör `/usr/libexec/java_home -v 21`. Saknas JDK 21: `brew install --cask temurin@21`. Förväntat: en sökväg till JDK 21.

- [ ] **Steg 2: Skriv röktestet**

`SmokeTest.kt`: `@Test fun modulenFinns() { assertEquals("se.hardyson.sophamtning.core", CoreInfo.PACKAGE) }`.

- [ ] **Steg 3: Kör det och se det fallera**

Run: `cd Android && ./gradlew :core:test`
Förväntat: kompileringsfel, `CoreInfo` finns inte.

- [ ] **Steg 4: Projektet och `object CoreInfo { const val PACKAGE = "se.hardyson.sophamtning.core" }`**

Wrappern skapas med `gradle wrapper --gradle-version <version>` från `Android/`. `settings.gradle.kts` har `rootProject.name = "Sophamtning"` och `include(":core")`. `core` använder `kotlin("jvm")` och `kotlin("plugin.serialization")` ur katalogen. `.gitignore` utesluter `.gradle/`, `build/`, `local.properties` och `.idea/`.

- [ ] **Steg 5: Kör testet**

Run: `cd Android && ./gradlew :core:test`
Förväntat: `BUILD SUCCESSFUL`, 1 test.

- [ ] **Steg 6: Commit**

```bash
git add Android
git commit -m "build: Gradle-projektet för Android med modulen core"
```

### Uppgift 2: Datum i Stockholm

**Filer:**
- Skapa: `Android/core/src/main/kotlin/se/hardyson/sophamtning/core/dates/DayDate.kt`, `StockholmClock.kt`, `SwedishFormat.kt`
- Test: `Android/core/src/test/kotlin/se/hardyson/sophamtning/core/dates/DatesTest.kt`

**Gränssnitt:**
- Ger:
  - `@Serializable(with = DayDateSerializer::class) data class DayDate(val year: Int, val month: Int, val day: Int) : Comparable<DayDate>`, med `companion fun parse(iso: String): DayDate?`, `val iso: String`, `fun plusDays(days: Int): DayDate` och `fun daysUntil(other: DayDate): Int`. Serialiseras som `"YYYY-MM-DD"`, och ett ogiltigt datum ger ett avkodningsfel.
  - `object StockholmClock { val zone: ZoneId; fun today(now: Instant = Instant.now()): DayDate; fun at(day: DayDate, hour: Int, minute: Int): Instant }`.
  - `object SwedishFormat` med samma funktioner och texter som `SwedishFormat.swift`.

- [ ] **Steg 1: Skriv testerna**

Skriv om de fyra testerna i `DatesTests.swift` med samma namn och värden (`idagFoljerStockholmEfterMidnatt`, `artonNollNollVidOmstallning`, `svenskaTexter`, `ogiltigtDatumGerNil`), och lägg till `isoTurOchRetur`: `DayDate.parse("2026-11-17")!!.iso == "2026-11-17"`, `plusDays(14) == DayDate(2026, 12, 1)` och `daysUntil` mellan dem är `14`.

- [ ] **Steg 2: Se dem fallera**

Run: `cd Android && ./gradlew :core:test --tests '*DatesTest*'`
Förväntat: kompileringsfel.

- [ ] **Steg 3: Implementera med `java.time`**

`DayDate` bygger på `LocalDate`, och `StockholmClock` på `ZoneId.of("Europe/Stockholm")`. Telefonens tidszon används aldrig.

- [ ] **Steg 4: Kör testerna, också i en annan tidszon**

Run: `cd Android && ./gradlew :core:test --tests '*DatesTest*' && TZ=America/New_York ./gradlew :core:test --tests '*DatesTest*' --rerun`
Förväntat: gröna båda gångerna.

- [ ] **Steg 5: Commit**

```bash
git add Android/core
git commit -m "build: datum i Stockholm i Android-kärnan"
```

### Uppgift 3: API-modellerna och klienten

**Filer:**
- Skapa: `Android/core/src/main/kotlin/se/hardyson/sophamtning/core/api/ApiModels.kt`, `Lenient.kt`, `ApiError.kt`, `SoporApi.kt`, `SoporClient.kt`
- Ändra: `Android/core/build.gradle.kts` (testresurserna)
- Test: `Android/core/src/test/kotlin/se/hardyson/sophamtning/core/api/SoporClientTest.kt`, `SourceMessageDecodingTest.kt`

**Gränssnitt:**
- Tar: `DayDate` från uppgift 2.
- Ger:
  - Datatyperna i `APIModels.swift` med samma namn och fält: `SearchHit`, `AreaDetails`, `AreaSource`, `SchedulePeriod`, `Pickups`, `SearchResponse`, `Address`, `NextPickup`, `Deviation`, `PickupEvent`, `Bin`, `FractionInfo`, `Links`, `AddressResponse`, `SourceMessage`, `SourcesResponse` och källtypen i den. Webbadresser är `String`, och de regler som iOS har för en ogiltig adress (fel eller `null`, per fält) gäller oförändrade. Standardvärden och reserver (till exempel att `selection` saknas och blir `"address"`, och att `messages` blir `[]`) är exakt de i `init(from:)` i `APIModels.swift`.
  - `sealed interface ApiError` (som `Exception`): `BadRequest`, `NotFound`, `SourceUnavailable`, `Network`, `Unexpected(val status: Int)`.
  - `interface SoporApi` med `suspend fun search(query: String, source: String?): SearchResponse`, `suspend fun areas(place: String): SearchResponse`, `suspend fun areas(place: String, lastEmptied: DayDate): SearchResponse`, `suspend fun address(url: String): AddressResponse` och `suspend fun sources(): SourcesResponse`.
  - `class SoporClient(engine: HttpClientEngine, version: String) : SoporApi`. Bara oreserverade tecken (`A–Z a–z 0–9 - . _ ~`) lämnas okodade i frågan, så också `+` och `,` kodas. `address(url)` hämtar `url` oförändrad. Status 400, 404 och 502 ger `BadRequest`, `NotFound` och `SourceUnavailable`. Andra statusar och svar som inte går att tolka ger `Unexpected(status)`. Nät- och tidsfel ger `Network`, och avbrott (`CancellationException`) kastas vidare. `sources()` filtrerar bort `testData`.

- [ ] **Steg 1: Testresurserna från iOS**

I `core/build.gradle.kts`: `sourceSets.test.resources.srcDir("../../iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/Fixtures")`. En kommentar säger att fixturerna delas med iOS och inte kopieras.

- [ ] **Steg 2: Skriv testerna**

`SoporClientTest.kt` skriver om alla tester i `APIClientTests.swift` med samma namn, fixturer och förväntade värden, och med `MockEngine` i stället för iOS-testernas URL-protokoll. Testet med statuskoderna heter `statuskoderMappas` och täcker `400→BadRequest`, `404→NotFound`, `502→SourceUnavailable` och `500→Unexpected(500)`. `sokningKodarQueryOchSkickarUserAgent` kontrollerar `User-Agent: Sophamtning-Android/9.9.9` och `Accept: application/json`.

`SourceMessageDecodingTest.kt` skriver om avkodningstesterna i `SourceMessagesTests.swift` (`adressvaretMedMeddelanden`, `adressvaretUtanMeddelandenGerTomLista`, `ettTrasigtMeddelandeFallerInteDeAndra`) med `adress.json`.

- [ ] **Steg 3: Se dem fallera**

Run: `cd Android && ./gradlew :core:test`
Förväntat: kompileringsfel.

- [ ] **Steg 4: Implementera modellerna, `Lenient` och klienten**

`Json { ignoreUnknownKeys = true }`. `Lenient` motsvarar iOS: en lista där ett element som inte går att avkoda tas bort, och ett fält som är trasigt blir sitt standardvärde. Ktor-klienten får `ContentNegotiation` bara om det inte krockar med den förlåtande avkodningen. Annars avkodas kroppen för hand med `Json`.

- [ ] **Steg 5: Kör testerna, också i en annan tidszon**

Run: `cd Android && ./gradlew :core:test && TZ=America/New_York ./gradlew :core:test --rerun`
Förväntat: gröna båda gångerna, och lika många tester som i `APIClientTests.swift` plus de tre om meddelanden.

- [ ] **Steg 6: Ett riktigt anrop mot API:t (för hand, inte i CI)**

Ett test med `@Ignore`-markering eller en egen Gradle-uppgift, `kontraktMotRiktigaApiet`, anropar `sources()` och `search("Storgatan", null)` mot produktionen med OkHttp-motorn, som `ContractTests` på iOS. Kör det en gång lokalt. Förväntat: inga fel och minst en källa.

- [ ] **Steg 7: Commit**

```bash
git add Android/core
git commit -m "build: API-modeller och klient för Sopor i Android-kärnan"
```

### Uppgift 4: Appen startar med temat

**Filer:**
- Skapa: `Android/app/build.gradle.kts`, `Android/app/src/main/AndroidManifest.xml`, `Android/app/src/main/kotlin/se/hardyson/sophamtning/MainActivity.kt`, `.../ui/theme/Theme.kt`, `.../ui/theme/Type.kt`, `.../ui/theme/Color.kt`, `Android/app/src/main/res/values/strings.xml`, appikonen som adaptiv ikon
- Ändra: `Android/settings.gradle.kts` (`include(":app")`)
- Test: `Android/app/src/test/kotlin/se/hardyson/sophamtning/MainActivityTest.kt`

**Gränssnitt:**
- Tar: `:core`, `Android/version.txt`.
- Ger: `@Composable fun SophamtningTheme(content: @Composable () -> Unit)` med `dynamicColor` alltid av, ljust och mörkt schema med färgerna i `SophamtningDesign/Theme` på iOS, och `Typography` med Fredoka för rubriker och Nunito för text. `MainActivity` med kant-till-kant-layout som visar rubriken **Sophämtning**.

- [ ] **Steg 1: Skriv testet**

`MainActivityTest` med Robolectric och `createAndroidComposeRule<MainActivity>()`: `onNodeWithText("Sophämtning").assertIsDisplayed()`. Ett andra test, `versionenKommerFranVersionTxt`, kontrollerar att `BuildConfig.VERSION_NAME` är innehållet i `Android/version.txt`.

- [ ] **Steg 2: Se det fallera**

Run: `cd Android && ./gradlew :app:testDebugUnitTest`
Förväntat: fel, eftersom `:app` saknas.

- [ ] **Steg 3: Appen**

- Typsnitten: en Gradle-uppgift kopierar `Fredoka.ttf` och `Nunito.ttf` från `iOS/Packages/SophamtningKit/Sources/SophamtningDesign/Resources/Fonts/` till en genererad `res/font/` som `fredoka.ttf` och `nunito.ttf`, och registreras som genererade resurser för alla varianter.
- `versionName` läses från `version.txt`. `versionCode` är `1` lokalt och sätts i releasejobbet (plan 7).
- Färgerna tas ur iOS-temat (`SophamtningDesign`), med samma namn och värden för ljust och mörkt läge.
- Appikonen görs av iOS-appens ikon i `iOS/Sophamtning/Assets.xcassets`, som adaptiv ikon med förgrund och bakgrund.

- [ ] **Steg 4: Kör testerna och bygget**

Run: `cd Android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`
Förväntat: gröna tester, lint utan fel och en `app-debug.apk`.

- [ ] **Steg 5: Se appen i emulatorn**

Starta en emulator med API 36, installera med `./gradlew :app:installDebug`, öppna appen och ta en skärmbild i ljust och mörkt läge. Förväntat: rubriken i Fredoka, appens färger och inga dynamiska färger. Skicka skärmbilderna till Jesper.

- [ ] **Steg 6: Commit**

```bash
git add Android
git commit -m "build: Android-appen startar med Sophämtnings tema"
```

### Uppgift 5: CI och Release Please för Android

**Filer:**
- Skapa: `.github/workflows/android.yml`
- Ändra: `release-please-config.json`, `.release-please-manifest.json`, `.github/workflows/release.yml` (testbyggets commit-lista)

**Gränssnitt:**
- Ger: den obligatoriska kontrollen `android` (jobbnamn), och Release Please utdata `Android--release_created` och `Android--tag_name` (används i plan 7).

- [ ] **Steg 1: `android.yml`**

Samma mönster som `ios.yml`: jobbet `changes` på `ubuntu-latest` sätter `android=true` när PR:en ändrar något under `Android/`, `.github/workflows/android.yml`, `release-please-config.json`, `.release-please-manifest.json` eller de delade filerna: `iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/Fixtures/`, `iOS/Sophamtning/UITestData/`, `iOS/Packages/SophamtningKit/Sources/SophamtningKit/Kommun/Resources/` och `iOS/Packages/SophamtningKit/Sources/SophamtningDesign/Resources/Fonts/`. Jobbet `android` har `needs: changes` och `if: ${{ !cancelled() && needs.changes.outputs.android != 'false' }}`, och körs på `ubuntu-latest` med `actions/setup-java` (Temurin 21) och `gradle/actions/setup-gradle`, pinnade på commit-SHA med versionen som kommentar. Stegen: `./gradlew :core:test`, `TZ=America/New_York ./gradlew :core:test --rerun`, `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`, alla med `working-directory: Android`.

- [ ] **Steg 2: Komponenten `android`**

I `release-please-config.json` får `packages` paketet `"Android": { "component": "android" }`. Versionstypen `simple` uppdaterar `Android/version.txt` och `Android/CHANGELOG.md`. Manifestet får `"Android": "0.0.0"`.

- [ ] **Steg 3: Testbyggets commits bara för iOS**

I `release.yml`, steget "Vad ska testas och Nyheter": `git log … ${last_tag:+"$last_tag..HEAD"} -- iOS scripts`, så att Android-commits inte hamnar i TestFlight.

- [ ] **Steg 4: Kontrollera**

Run: `actionlint .github/workflows/*.yml` och torrkörningen av Release Please från plan 1 (uppgift 1, steg 4) med grenen.
Förväntat: inga fel i actionlint, och torrkörningen visar sökvägarna `iOS` och `Android` utan några release-PR:er, eftersom planens commits inte är `feat:` eller `fix:`.

- [ ] **Steg 5: Commit**

```bash
git add .github/workflows/android.yml .github/workflows/release.yml release-please-config.json .release-please-manifest.json
git commit -m "ci: Android-tester i CI och komponenten android i Release Please"
```

### Uppgift 6: Dokumentationen och PR:en

**Filer:**
- Ändra: `CLAUDE.md`, `README.md` (tabellen över mapparna)

- [ ] **Steg 1: CLAUDE.md**

- Repots delar: `Android/` med `core/` (ren Kotlin, logik och API) och `app/` (Compose-appen), och att fixturer, ortlista och typsnitt läses från `iOS/`.
- Kommandon: `cd Android && ./gradlew :core:test`, `./gradlew :app:testDebugUnitTest`, `./gradlew :app:assembleDebug` och `./gradlew :app:installDebug`.
- Regler: lägsta version Android 12 (API 31), User-Agent `Sophamtning-Android/<version>` och `applicationId` `se.hardyson.sophamtning`. Raden om iOS-versionen och User-Agent för iOS står kvar.
- Releaser: komponenten `android` med `Android/version.txt` och `Android/CHANGELOG.md`, och den obligatoriska kontrollen `android`.

- [ ] **Steg 2: README**

Raden för `Android/` blir "Android-appen, under arbete".

- [ ] **Steg 3: Commit och PR**

```bash
git add CLAUDE.md README.md
git commit -m "docs: Android i CLAUDE.md och README"
```

PR med titeln `build: Grunden för Android-appen`, med PR-mallens rubriker och skärmbilderna från uppgift 4. Efter mergen lägger Jesper till `android` som obligatorisk kontroll i regeluppsättningen för `main`.
