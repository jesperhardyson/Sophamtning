# Android 7: Google Play

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** En Android-release görs som en iOS-release:
1. Jesper mergar release-PR:en för `android`.
2. Jobbet **Google Play** väntar på hans godkännande i miljön `googleplay`.
3. Jobbet bygger en signerad AAB och laddar upp den till **intern testning** med "Vad är nytt" från changelogen.

En körning för hand gör ett testbygge eller laddar upp en release igen, och rör bara den app som väljs. Den första releasen blir Android 1.0.0.

**Arkitektur:**
- **Signering och bygge:**
  - `app/build.gradle.kts` får en signering för release som läser uppladdningsnyckeln från miljövariabler, och R8 med regler för kotlinx.serialization, Ktor och Glance.
  - `versionCode` räknas i jobbet som `github.run_number × 100 + github.run_attempt`, som byggnumret på iOS.
- **Workflow:** `release.yml` får jobbet `googleplay` bredvid `testflight`, med utdata för sökvägen `Android` från Release Please. Körning för hand får valet `app`.
- **Uppladdning:** ett eget skript, `scripts/play_upload.py`, anropar Play Developer API. Det motsvarar `release_notes.py` för App Store Connect och behöver ingen tredjeparts-action.

**Teknik:** Android Gradle Plugin (signering, R8, `bundleRelease`), Google Play Developer API v3 (`edits`, `bundles`, `tracks`, `listings`) via ett tjänstkonto, Python med `google-auth` och `requests` i en venv, som i dagens releaseskript, och GitHub Actions.

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnitten Release och CI och Google Play. `docs/specs/2026-11-08-release.md` är facit för hur iOS-flödet ser ut.

## Gemensamma krav

- **Inga hemligheter i repot.** Nyckeln och tjänstkontot finns bara som secrets i miljön `googleplay`. De skrivs till tillfälliga filer i jobbet och tas bort i ett steg med `if: always()`, som App Store Connect-nyckeln.
- **Paketnamnet** är `se.hardyson.sophamtning`, och det första bygget till Play måste ha det.
- **"Vad är nytt"** (`sv-SE`) är versionens avsnitt ur changelogen som ren text, utan länkar och PR-nummer, och högst 500 tecken. Längre text kortas vid en hel rad, och "…" läggs till.
- **En körning för hand rör bara den valda appen.** En iOS-release startar aldrig Google Play, och tvärtom.
- **Actions** pinnas på commit-SHA med versionen som kommentar, som i dag.

## Granskningsfokus

1. **En release av iOS** startar jobbet Google Play, eller en release av Android startar TestFlight. Förväntat: varje jobb körs bara för sin egen komponent och sitt eget val vid körning för hand.
2. **`versionCode`** blir lägre än en tidigare uppladdning, eller krockar mellan ett testbygge och en release. Förväntat: den ökar alltid, i samma workflow.
3. **Release-bygget kraschar** efter R8 men inte i debug, till exempel avkodningen med kotlinx.serialization eller Glance. Förväntat: ett röktest av release-bygget i emulatorn före PR:en.
4. **En changelog som är längre än 500 tecken**, eller innehåller länkar och PR-nummer. Förväntat: kortad vid en hel rad, och ren text.
5. **Nyckeln eller tjänstkontot** syns i loggen eller blir kvar på runnern. Förväntat: aldrig utskrivna, och filerna tas alltid bort.

---

### Uppgift 1: Signering och release-bygge

**Filer:**
- Ändra: `Android/app/build.gradle.kts` (`signingConfigs.release` från `SOPHAMTNING_UPLOAD_KEYSTORE`, `_PASSWORD`, `_KEY_ALIAS` och `_KEY_PASSWORD`, och `buildTypes.release` med `isMinifyEnabled` och `isShrinkResources`)
- Skapa: `Android/app/proguard-rules.pro`
- Test: `app/src/test/.../ReleaseConfigTest.kt` och ett röktest i emulatorn

- [ ] **Steg 1: Skriv testet** `releaseUtanNyckelByggsInteTystOsignerad`: utan miljövariablerna stoppar `bundleRelease` med ett tydligt fel, så att ett osignerat bygge aldrig når Play. Lokalt kan release-bygget signeras med debug-nyckeln, men bara om `-Psigning=debug` ges, och bara för att prova i emulatorn. Se testet fallera.
- [ ] **Steg 2: Implementera**, med regler för kotlinx.serialization (`@Serializable`-klasser och deras serialiserare), Ktor och OkHttp, och Glance.
- [ ] **Steg 3: Röktest:**
  - Bygg `assembleRelease -Psigning=debug`.
  - Installera i emulatorn som en egen kopia, så att Jespers data inte rörs.
  - Kontrollera att söka, spara en adress, öppna adressvyn, Utställt, inställningarna och widgeten fungerar efter R8.
  - Skriv resultatet i checklistan.
- [ ] **Steg 4: Kör** `cd Android && ./gradlew :core:test :app:testDebugUnitTest :app:lintRelease :app:assembleDebug`. Förväntat: gröna.
- [ ] **Steg 5: Commit** `build: signerat release-bygge med R8 på Android`

### Uppgift 2: Uppladdningen till Google Play

**Filer:**
- Skapa: `scripts/play_upload.py` och `scripts/test_play_upload.py`
- Ändra: CI-steget "Releaseskriptens tester" i `ios.yml`, som redan kör `python3 -m unittest discover -s scripts`, och `android.yml`, som kör samma tester när `scripts/` ändras

**Gränssnitt:** `play_upload.py upload --aab <fil> --track internal --notes-file <fil> --package se.hardyson.sophamtning`. Skriptet läser tjänstkontot från `PLAY_SERVICE_ACCOUNT_PATH`. Det skapar en edit, laddar upp bundlen, sätter spåret med "Vad är nytt" på `sv-SE` och status `completed` (intern testning), och gör commit på editen. Det skriver aldrig ut nycklar.

- [ ] **Steg 1: Skriv testerna:**
  - `vadArNyttArRenTextUtanLankar`, med samma tolkning av changelogen som `release_notes.py`
  - `vadArNyttKortasVidHelRadTill500Tecken`
  - `uppladdningenGorEditBundleTrackOchCommit`, med ett fejkat API
  - `felFranApietStopparMedTydligtMeddelande`

  Se dem fallera.
- [ ] **Steg 2: Implementera.**
- [ ] **Steg 3: Kör** `python3 -m unittest discover -s scripts`. Förväntat: gröna.
- [ ] **Steg 4: Commit** `ci: uppladdning till Google Play`

### Uppgift 3: Jobbet Google Play i Release

**Filer:**
- Ändra: `.github/workflows/release.yml`

Så fungerar det:
- `release-please` får utdata för `Android--release_created` och `Android--tag_name`, och `testflight` får sina utdata med nya namn.
- `workflow_dispatch` får valet `app` (`ios` eller `android`). `testflight` körs bara för `ios`, och `googleplay` bara för `android`.
- Jobbet **googleplay** körs på `ubuntu-latest` i miljön `googleplay`, med Temurin 21 och `setup-gradle`. Det har stegen:
  1. versionen och `versionCode`,
  2. nyckeln och tjänstkontot till tillfälliga filer,
  3. `bundleRelease -PversionCode=…`,
  4. "Vad är nytt" från GitHub Releasen, eller "Testbygge från `<gren>` (`<commit>`)" och commits för Android sedan senaste `android-v`-taggen,
  5. `play_upload.py`,
  6. städning med `if: always()`,
  7. AAB och mapping-filen sparas som artefakt i 30 dagar, för att kunna läsa kraschrapporter.
- Ett testbygge får nästa patchversion efter `Android/version.txt`, och ingen fil i repot ändras.

- [ ] **Steg 1:** Skriv jobbet, och kontrollera det med `actionlint .github/workflows/*.yml` utan fel.
- [ ] **Steg 2:** Kontrollera villkoren med en tabell i commit-meddelandet, eller i en kommentar: push med en iOS-release, push med en Android-release, körning för hand med `ios` och med `android`, med och utan tagg. Varje fall startar rätt jobb.
- [ ] **Steg 3: Commit** `ci: jobbet Google Play i Release`

### Uppgift 4: Dokumentationen och PR:en

**Filer:**
- Ändra: `CLAUDE.md` (Releaser för Android: miljön `googleplay`, secrets, intern testning och körning för hand med `app`), `docs/specs/2026-11-08-release.md` (ett avsnitt "Ändrat 2026-11-23: Google Play"), och README
- Skapa: `docs/android-google-play.md`, med Jespers engångssteg i Play Console:
  1. skapa appen,
  2. skapa uppladdningsnyckeln med `keytool`,
  3. bygga och ladda upp det första bygget för hand, och slå på Play App Signing,
  4. skapa tjänstkontot, ge det Play Developer API och behörighet i Play Console,
  5. skapa miljön `googleplay` med godkännare och secrets,
  6. starta ett slutet test med 12 testare i 14 dagar,
  7. fylla i datasäkerheten (inga data samlas in), åldersgränsen och integritetspolicyn.

- [ ] **Steg 1:** Skriv dokumenten.
- [ ] **Steg 2:** Kör hela sviten och `actionlint`.
- [ ] **Steg 3:** PR med titeln `ci: Google Play-releaser för Android`. Den ger ingen release.

### Uppgift 5: Den första releasen (efter att Jesper har gjort stegen i Play Console)

- [ ] **Steg 1:** Jesper startar Release för hand med `app: android` och tomt taggfält. Förväntat: ett testbygge i intern testning med `versionName` 0.0.1.
- [ ] **Steg 2:** En PR med titeln `feat: Android-appen`. Den sätter `"release-as": "1.0.0"` på paketet `Android` i `release-please-config.json`, och ändrar en fil i `Android/` (till exempel en README för Android-mappen), så att commiten räknas till Android. En footer `Release-As:` används inte, eftersom den inte säkert följer med vid squash-merge. Efter mergen öppnar Release Please release-PR:en `android 1.0.0`.
- [ ] **Steg 3:** Jesper mergar release-PR:en och godkänner `googleplay`. Förväntat: version 1.0.0 i intern testning, med "Vad är nytt" från changelogen.
- [ ] **Steg 4:** En PR med titeln `ci: Android släpps med vanliga versioner` tar bort `release-as` ur konfigurationen, så att nästa `fix:` ger 1.0.1.
