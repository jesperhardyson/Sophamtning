# Android 1: Release och CI per app

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans för att genomföra planen uppgift för uppgift. Stegen har kryssrutor (`- [ ]`).

**Mål:** iOS blir en egen komponent i Release Please, med taggen `ios-vX.Y.Z`, och CI:s obligatoriska kontroll `test` klarar PR:er som inte rör iOS. Ingen Android-kod ännu.

**Arkitektur:** `release-please-config.json` får paketet `iOS` med komponenten `ios`. `CHANGELOG.md` och `version.txt` flyttas till `iOS/`. Workflowerna läser Release Please utdata per sökväg (`iOS--release_created`, `iOS--tag_name`) och tål både gamla `v`-taggar och nya `ios-v`-taggar. `ios.yml` får ett första jobb som avgör om iOS har ändrats.

**Teknik:** Release Please (`googleapis/release-please-action` v5, manifest), GitHub Actions, xcodegen.

**Spec:** `docs/specs/2026-11-23-android-app.md`, avsnittet Release och CI.

## Planerna för Android

Specen är uppdelad i planer som var och en kan mergas för sig. Den här är den första. De andra skrivs när den förra är mergad, så att de kan bygga på det som faktiskt finns.

1. **Release och CI per app** (den här).
2. **Android-grunden:** Gradle-projektet med `core` och `app`, API-modeller och avkodning mot iOS-fixturerna, `android.yml` och komponenten `android` i Release Please.
3. **Logiken i `core`:** schemalogik, kommunkoll, påminnelseplaneraren, källmeddelanden, Nyheter och lagringen, med iOS-testerna omskrivna.
4. **Appens skärmar:** tema, kärlet, hem, sökning, adressvy, hela schemat, inställningar, Nyheter och webblänkar.
5. **Påminnelser och bakgrund:** notiser, alarm, exakta tider, Live Update, WorkManager, och omregistrering efter omstart och tidszonbyte.
6. **Utanför appen:** widgetar, rutan i snabbinställningarna, genvägar och Google Kalender.
7. **Google Play:** releasejobbet, körning för hand med val av app, "Vad är nytt", UI-test och tillgänglighet på emulator, och checklistan för en riktig telefon.

## Gemensamma krav

- Commit-meddelanden och PR-titlar på svenska, Conventional Commits, utan AI-attributionsrader. Hela den här planen är `ci:` och `docs:`, så den ger ingen release.
- iOS-versionen är och förblir 1.3.1 tills nästa `feat:` eller `fix:` i `iOS/`. Version och changelog ändras aldrig för hand, utöver flytten av filerna.
- Gamla taggar `v1.0.0` till `v1.3.1` och deras GitHub Releases ligger kvar orörda.
- Actions pinnas på commit-SHA med versionen som kommentar, som i dag.

## Granskningsfokus

1. **Release Please hittar inte förra releasen** och föreslår 1.0.0 eller tar med hela historiken i changelogen. Förväntat: nästa release-PR för iOS föreslår 1.3.2 eller 1.4.0 med bara commits efter `v1.3.1`. Kontrolleras med en torrkörning i uppgift 1.
2. **En omladdning för hand med en gammal tagg** (`v1.3.1`) ger versionen `v1.3.1` eller `ios-1.3.1`. Förväntat: `1.3.1`. Kontrolleras i uppgift 2.
3. **Nyheter i appen blir tomt** efter flytten, eftersom `CHANGELOG.md` inte följer med i bygget. Förväntat: samma versioner som i 1.3.1. Kontrolleras i uppgift 1, steg 6.
4. **En PR som bara ändrar `docs/`** blir hängande på kontrollen `test`. Förväntat: `test` hoppas över och räknas som godkänd. Kontrolleras i uppgift 3.
5. **Testbyggets text i TestFlight** tar med commits ända från `v1.3.1`, eftersom `git describe` inte hittar en `ios-v`-tagg. Förväntat: commits sedan senaste iOS-taggen, gammal eller ny. Kontrolleras i uppgift 2.

---

### Uppgift 1: iOS som komponent i Release Please

**Filer:**
- Flytta: `CHANGELOG.md` → `iOS/CHANGELOG.md`, `version.txt` → `iOS/version.txt`
- Ändra: `release-please-config.json`, `.release-please-manifest.json`, `iOS/project.yml:34`, `iOS/Sophamtning.xcodeproj` (genereras)

**Gränssnitt:**
- Ger: Release Please utdata `iOS--release_created` och `iOS--tag_name` (till exempel `ios-v1.4.0`), `iOS/version.txt` och `iOS/CHANGELOG.md`.

- [ ] **Steg 1: Flytta filerna med historiken**

```bash
git mv CHANGELOG.md iOS/CHANGELOG.md
git mv version.txt iOS/version.txt
```

- [ ] **Steg 2: Skriv om konfigurationen**

`release-please-config.json`: behåll `$schema`, `release-type` och hela `changelog-sections`. Sätt `"include-component-in-tag": true` och `"bootstrap-sha"` till commiten som taggen `v1.3.1` pekar på (`git rev-list -n 1 v1.3.1`). Byt `packages` till:

```json
"packages": {
  "iOS": {
    "component": "ios",
    "extra-files": [{ "type": "generic", "path": "Config/Version.xcconfig" }]
  }
}
```

`.release-please-manifest.json` blir `{ "iOS": "1.3.1" }`.

- [ ] **Steg 3: Peka om changelogen i bygget**

I `iOS/project.yml` blir `- path: ../CHANGELOG.md` till `- path: CHANGELOG.md`, med kommentaren kvar. Kör `cd iOS && xcodegen generate`.

- [ ] **Steg 4: Torrkör Release Please mot GitHub**

Kör från grenen efter att den är pushad:

```bash
npx --yes release-please@17 release-pr --dry-run \
  --repo-url jesperhardyson/Sophamtning --target-branch feature/android-app \
  --token "$(gh auth token)" --config-file release-please-config.json --manifest-file .release-please-manifest.json
```

Förväntat: inget förslag på release, eller ett förslag för `ios` på 1.3.2 eller 1.4.0 med bara commits efter `v1.3.1`. Föreslås 1.0.0, eller kommer äldre commits med, är `bootstrap-sha` fel eller ignorerad. Sätt i så fall `last-release-sha` på paketet `iOS` i stället och kör igen. Byt `release-please@17` mot den version som motsvarar `release-please-action` v5 om versionen inte stämmer.

- [ ] **Steg 5: Bygg och kör paketets tester**

```bash
cd iOS/Packages/SophamtningKit && swift test --skip ContractTests
xcodebuild -project iOS/Sophamtning.xcodeproj -scheme Sophamtning -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Förväntat: alla tester gröna och `BUILD SUCCEEDED`.

- [ ] **Steg 6: Kontrollera att changelogen följer med appen**

```bash
find ~/Library/Developer/Xcode/DerivedData -path '*Sophamtning.app/CHANGELOG.md' -newer iOS/CHANGELOG.md | head -1
```

Förväntat: en sökväg. Starta appen i simulatorn och öppna Inställningar → Version. Arket Nyheter visar 1.3.1 överst.

- [ ] **Steg 7: Commit**

```bash
git add -A iOS/CHANGELOG.md iOS/version.txt release-please-config.json .release-please-manifest.json iOS/project.yml iOS/Sophamtning.xcodeproj
git commit -m "ci: iOS som egen komponent i Release Please"
```

### Uppgift 2: Workflowerna läser iOS-komponenten

**Filer:**
- Ändra: `.github/workflows/release.yml`, `.github/workflows/appstore-notes.yml`

**Gränssnitt:**
- Tar: utdata från uppgift 1.
- Ger: jobbet `testflight` kör när `iOS--release_created` är `true`, eller för hand som i dag.

- [ ] **Steg 1: Release Please utdata per sökväg**

I `release.yml`, jobbet `release-please`: `release_created` blir `${{ steps.release.outputs['iOS--release_created'] }}` och `tag_name` blir `${{ steps.release.outputs['iOS--tag_name'] }}`. Jobbets namn och utdata behåller sina namn, så att `testflight` inte ändras mer än nedan.

- [ ] **Steg 2: Version från både gamla och nya taggar**

I steget Version: testbygget läser `iOS/version.txt`. En release ger `version="${TAG#ios-}"; version="${version#v}"`. Kommentaren uppdateras.

- [ ] **Steg 3: Testbyggets commits sedan senaste iOS-taggen**

I steget "Vad ska testas och Nyheter": `git describe --tags --abbrev=0 --match 'ios-v*' --match 'v*'`. Beskrivningen av fältet `tag` i `workflow_dispatch` blir "… till exempel ios-v1.4.0 eller v1.3.1 …".

- [ ] **Steg 4: App Store-text**

I `appstore-notes.yml` räknas versionen på samma sätt som i steg 2, och beskrivningen av `tag` ändras som i steg 3.

- [ ] **Steg 5: Kontrollera syntaxen och versionsraden**

```bash
for t in v1.3.1 ios-v1.4.0; do TAG=$t; v="${TAG#ios-}"; echo "$t -> ${v#v}"; done
gh workflow view release.yml >/dev/null && echo ok
```

Förväntat: `v1.3.1 -> 1.3.1` och `ios-v1.4.0 -> 1.4.0`. Kör `actionlint` om det finns installerat, utan fel.

- [ ] **Steg 6: Commit**

```bash
git add .github/workflows/release.yml .github/workflows/appstore-notes.yml
git commit -m "ci: Release och App Store-text läser iOS-komponentens tagg"
```

### Uppgift 3: Kontrollen `test` klarar PR:er utan iOS

**Filer:**
- Ändra: `.github/workflows/ios.yml`

**Gränssnitt:**
- Ger: jobbet `changes` med utdata `ios` (`true` eller `false`). Plan 2 lägger till `android` på samma sätt i `android.yml`.

- [ ] **Steg 1: Jobbet `changes`**

Ett nytt första jobb på `ubuntu-latest` som checkar ut med `fetch-depth: 0` och sätter utdata `ios=true` när `git diff --name-only "${{ github.event.pull_request.base.sha }}" HEAD` har någon fil under `iOS/` eller `scripts/`, eller är någon av `.github/workflows/ios.yml`, `.github/workflows/release.yml`, `release-please-config.json` och `.release-please-manifest.json`. Annars `ios=false`.

- [ ] **Steg 2: `test` beror på `changes`**

Jobbet `test` behåller namnet, eftersom regeluppsättningen kräver kontrollen `test`. Det får `needs: changes` och `if: needs.changes.outputs.ios == 'true'`. En kommentar förklarar att ett överhoppat jobb räknas som godkänt, och att filtret därför inte ligger i `on:`.

- [ ] **Steg 3: Kontrollera på PR:en**

PR:en för den här planen ändrar `iOS/`, så `test` ska köras och bli grön. Efter mergen öppnas en liten PR som bara ändrar en rad i `docs/` (till exempel planens kryssrutor). Förväntat: `changes` körs, `test` står som överhoppad, och PR:en går att merga.

- [ ] **Steg 4: Commit**

```bash
git add .github/workflows/ios.yml
git commit -m "ci: iOS-jobbet hoppas över när iOS inte har ändrats"
```

### Uppgift 4: Dokumentationen följer med

**Filer:**
- Ändra: `CLAUDE.md` (avsnitten Repots delar och Releaser), `docs/specs/2026-11-08-release.md`, `README.md` (om den nämner `version.txt` eller taggarna)

- [ ] **Steg 1: CLAUDE.md**

Avsnittet Releaser: taggen är `ios-vX.Y.Z` (äldre releaser har `vX.Y.Z`), changelogen och versionen ligger i `iOS/CHANGELOG.md` och `iOS/version.txt`, och `MARKETING_VERSION` ska vara densamma som `iOS/version.txt`. En rad om att en commit räknas till den app vars filer den ändrar, och att ändringar bara i `docs/`, `scripts/` eller roten inte ger någon release. En rad om jobbet `changes` och att kontrollen `test` hoppas över när iOS inte har ändrats.

- [ ] **Steg 2: Releasespecen**

`docs/specs/2026-11-08-release.md` får ett avsnitt "Ändrat 2026-11-23, godkänt av Jesper" med samma innehåll i kort form och en hänvisning till `2026-11-23-android-app.md`. Tidigare text skrivs inte om.

- [ ] **Steg 3: Commit**

```bash
git add CLAUDE.md docs/specs/2026-11-08-release.md README.md
git commit -m "docs: release per app i CLAUDE.md och releasespecen"
```

### Uppgift 5: PR och testbygge

- [ ] **Steg 1: PR**

Pusha grenen och öppna PR:en med titeln `ci: Release och CI per app inför Android`. Beskrivningen på svenska tar upp flytten, de nya taggarna, att inga gamla taggar ändras och resultatet av torrkörningen i uppgift 1.

- [ ] **Steg 2: Testbygge från grenen (Jesper)**

Jesper kör Actions > Release > Run workflow med grenen vald och tomt taggfält, och godkänner miljön `testflight`. Förväntat: version 1.3.2 i loggen, ett bygge i TestFlight och texten "Testbygge från feature/android-app (…)" med bara commits sedan `v1.3.1`. Nyheter i testbygget visar 1.3.1 överst.

- [ ] **Steg 3: Efter mergen**

Release Please kör på `main`. Förväntat: ingen ny release-PR, eftersom planen bara har `ci:` och `docs:`. Öppnas en release-PR för `ios` är den väntad först efter nästa `feat:` eller `fix:` i `iOS/`. Gör kontrollen i uppgift 3, steg 3.
