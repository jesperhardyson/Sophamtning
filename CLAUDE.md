# Sophämtning

Native-appar för iOS och Android som visar när sopkärlen töms. Apparna använder Sopor API v1. Hushållen har en egen liten server, brevlådan i `Server/`, som bara ser krypterade uppgifter.

## Repots delar

- `iOS/`: iOS-appen. `project.yml` är källan till `Sophamtning.xcodeproj`, som genereras med xcodegen och committas.
  - `iOS/Sophamtning/`: appen
  - `iOS/SophamtningWidgets/`: widgetar och Live Activity
  - `iOS/SophamtningUITests/`: UI-tester
  - `iOS/Packages/SophamtningKit/`: paketet med `SophamtningKit` (logik) och `SophamtningDesign` (tema och komponenter)
- `Android/`: Android-appen i Kotlin och Jetpack Compose. Gradle med versionskatalogen `gradle/libs.versions.toml`. Spec: `docs/specs/2026-11-23-android-app.md`.
  - `Android/core/`: ren Kotlin utan Android-API:er, med logik och API-klient, som `SophamtningKit`. Testerna körs på JVM.
  - `Android/app/`: Compose-appen med tema och komponenter
  - Fixturerna, ortlistan och typsnitten läses från `iOS/` och kopieras inte. En ändring i dem kör både iOS- och Android-testerna.
- `Server/`: brevlådan för hushåll, en Cloudflare Worker i TypeScript med ett Durable Object per hushåll. Spec: `docs/specs/2026-11-23-hushall-mellan-plattformar.md`. Den ger ingen release av någon app, och driftsätts från `main` av `.github/workflows/server.yml`.
  - `Server/test/vectors.json` är formatet för krypteringen. En kopia ligger i iOS-paketets `Fixtures` och läses också av Android. CI stoppar om de skiljer sig.
- `docs/specs/`: nya specar läggs här
- `docs/plans/`: nya planer läggs här
- `docs/design/`: Pencil-designen, som är facit för utseendet. Läs den via Pencil MCP, aldrig med Read eller Grep, eftersom `.pen`-filer är krypterade.

## Kommandon

```bash
# Generera projektet efter ändringar i iOS/project.yml
cd iOS && xcodegen generate

# Paketets tester
cd iOS/Packages/SophamtningKit && swift test

# Bygg appen
xcodebuild -project iOS/Sophamtning.xcodeproj -scheme Sophamtning -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Ett enskilt UI-test
xcodebuild -project iOS/Sophamtning.xcodeproj -scheme Sophamtning -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SophamtningUITests/CoreFlowTests/testLaggaTillAdressVisasPaHem

# Tillgänglighetsgranskningen och största texten, före release
xcodebuild -project iOS/Sophamtning.xcodeproj -scheme Granskning -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Servern (Node 22): tester, och kontroll av bygget utan att driftsätta
cd Server && npm ci --ignore-scripts && npm test && npx wrangler deploy --dry-run

# Hushållets synk mot den riktiga servern, lokalt
cd Server && npx wrangler dev --port 8799 --var LOCAL_ONLY_NO_JURISDICTION:1
cd iOS/Packages/SophamtningKit && HUSHALL_LOCAL=http://localhost:8799/v1 swift test --filter HouseholdServerTests

# Android (JDK 21): kärnans tester, appens tester, lint och bygge
cd Android && ./gradlew :core:test
cd Android && ./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug

# Android: installera på en emulator eller telefon
cd Android && ./gradlew :app:installDebug

# Android: kontraktstesterna mot det riktiga API:t, för hand
cd Android && ./gradlew :core:contractTest
```

UI-testerna är bara några få kärnflöden och tar cirka 3 minuter som hel svit. Kör bara de UI-tester som rör det som ändrats under arbetet, och hela sviten en gång innan PR:en görs redo eller mergas. Paketets tester och bygget körs varje gång. Nya kontroller av vad som visas och vilken text skrivs som enhetstester i paketet, inte som UI-tester.

## Regler

- Lägsta version är iOS 26 och Android 12 (API 31). Bas-URL är `https://sopor.hardyson.se/api/v1`.
- User-Agent är `Sophamtning-iOS/<version>` och `Sophamtning-Android/<version>`. Varje adress hämtas högst en gång i timmen.
- "I dag" och alla påminnelsetider räknas i `Europe/Stockholm`, oavsett telefonens tidszon.
- Notiser och Live Activities är avstängda från början. Inget schemaläggs utan användarens val.
  - Undantag: Meddelanden från källan är på från början, men en sådan notis skickas bara när iOS redan tillåter notiser, och appen frågar aldrig om tillstånd för den.
- Sparade `daysUntil`, `isToday`, `isTomorrow` och `text` visas aldrig. Adress-id tolkas och byggs aldrig om.
- Fraktioner visas alltid med färg, ikon och text. `estimated: true` visas som "ca" överallt.
- Tekniska fel får aldrig se ut som att en adress eller kommun saknas.
- Hushåll: bara brevlådans svar `removed` och `ended` tar bort ett hushåll i appen. Nycklar, inbjudningslänkar och namn loggas aldrig, och skickas aldrig okrypterade. Brevlådan har bas-URL `https://hushall.sopor.hardyson.se/v1`.
- Bundle-id är `se.hardyson.sophamtning`, och App Group är `group.se.hardyson.sophamtning`. På Android är `applicationId` `se.hardyson.sophamtning`.
- All text i appen, alla kommentarer och alla commit-meddelanden är på svenska.
- Commit-meddelanden och PR-titlar följer Conventional Commits och har inga AI-attributionsrader. Beskrivningen är på svenska.
  - `feat:` för ny funktion och `fix:` för rättning. Aldrig `feature:`.
  - `docs:`, `test:`, `ci:`, `chore:`, `refactor:` eller `build:` för det som inte ska ge en release, till exempel ändringar i spec och plan (`docs:`).
  - Ändringar som bryter något: `feat!:` och en rad `BREAKING CHANGE:`.

## Releaser

Releaser sköts med Release Please (googleapis/release-please-action), med versionstypen `simple`, i `.github/workflows/release.yml`. Spec: `docs/specs/2026-11-08-release.md`.

- Release Please läser commit-meddelandena på `main`: `feat:` höjer minor, `fix:` höjer patch och `!` höjer major. Andra typer ger ingen release och syns inte i changelogen.
- Repot squash-mergar, så PR-titeln blir commit-meddelandet på `main`. Titeln måste därför följa formatet ovan.
- Varje app är en egen komponent i Release Please, med egen version, changelog och tagg. iOS har `iOS/version.txt`, `iOS/CHANGELOG.md` och taggen `ios-vX.Y.Z`. Releaser före 1.3.2 har taggen `vX.Y.Z`. Spec: `docs/specs/2026-11-23-android-app.md`.
- En commit räknas till den app vars filer den ändrar. En commit som bara ändrar `docs/`, `scripts/` eller roten ger ingen release.
- Release Please håller en öppen release-PR per app med nästa version. När den mergas skapas appens tagg och en GitHub Release.
- Android har `Android/version.txt`, `Android/CHANGELOG.md` och taggen `android-vX.Y.Z`. Android släpps inte förrän appen är klar, så Android-commits är `build:`, `ci:`, `test:` eller `docs:` tills dess.
- När release-PR:en för Android mergas startar jobbet Google Play i samma körning. Det väntar på Jespers godkännande i miljön `googleplay`, bygger en AAB signerad med uppladdningsnyckeln och laddar upp den till intern testning med `scripts/play_upload.py`. "Vad är nytt" (`sv-SE`) är versionens avsnitt ur changelogen, som ren text och högst 500 tecken. `versionCode` är `run_number` × 100 + `run_attempt`, som byggnumret på iOS. Jesper flyttar själv en version till slutet test eller produktion i Play Console.
- Miljön `googleplay` har secrets `SOPHAMTNING_UPLOAD_KEYSTORE` (base64), `SOPHAMTNING_UPLOAD_KEYSTORE_PASSWORD`, `SOPHAMTNING_UPLOAD_KEY_ALIAS`, `SOPHAMTNING_UPLOAD_KEY_PASSWORD` och `PLAY_SERVICE_ACCOUNT_JSON` (base64), och tillåter bara grenen `main`, så att testbyggen för Android görs från `main`. Engångsstegen i Play Console och GitHub står i `docs/android-google-play.md`.
- Release-bygget har R8 och stoppar utan uppladdningsnyckeln. Lokalt kan det signeras med debug-nyckeln för att provas i en emulator: `./gradlew :app:assembleRelease -Psigning=debug`. `android.yml` bygger det på samma sätt i varje PR. Ett bygge med den riktiga nyckeln körs alltid med `--no-configuration-cache`, så att lösenorden inte sparas i Gradles konfigurationscache. Efter en ändring i `Android/app/proguard-rules.pro` görs ett röktest av release-bygget i emulatorn, med en separat kopia av appen.
- I `ios.yml` och `android.yml` avgör jobbet `changes` om appen har ändrats. Annars hoppas den obligatoriska kontrollen (`test` för iOS, `android` för Android) över, vilket räknas som godkänt.
- Innan release-PR:en mergas körs schemat `Granskning` (tillgänglighetsgranskningen och största texten, cirka 10 minuter). Det körs inte i den vanliga sviten.
- När release-PR:en för iOS mergas startar jobbet TestFlight i samma körning. Det väntar på Jespers godkännande i miljön `testflight`, och laddar sedan upp till App Store Connect. App Store-inskickning görs bara efter hans godkännande. En uppladdning kan göras om med Actions > Release > Run workflow, appen och taggen.
- Ett testbygge görs med Actions > Release > Run workflow, med en gren vald och tomt taggfält. Det får nästa patchversion efter appens `version.txt` och ändrar ingen fil i repot.
- En körning för hand har valet **app** (`ios` eller `android`) och rör bara den appen. En tagg som inte hör till appen stoppar jobbet.
- Appens version (`MARKETING_VERSION` i `iOS/Config/Version.xcconfig`) ska alltid vara densamma som i `iOS/version.txt`. Release Please uppdaterar båda. Byggnumret räknas fram i jobbet. Ändra aldrig version eller changelog för hand.
- Ändringar i specen godkänns av Jesper innan bygget fortsätter.
