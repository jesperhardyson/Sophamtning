# Sophämtning

Native-appar för iOS och Android som visar när sopkärlen töms. Här finns ingen egen backend. Appen använder bara Sopor API v1.

## Repots delar

- `iOS/`: iOS-appen. `project.yml` är källan till `Sophamtning.xcodeproj`, som genereras med xcodegen och committas.
  - `iOS/Sophamtning/`: appen
  - `iOS/SophamtningWidgets/`: widgetar och Live Activity
  - `iOS/SophamtningUITests/`: UI-tester
  - `iOS/Packages/SophamtningKit/`: paketet med `SophamtningKit` (logik) och `SophamtningDesign` (tema och komponenter)
- `Android/`: Android-appen, senare
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
xcodebuild -project iOS/Sophamtning.xcodeproj -scheme Sophamtning -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:SophamtningUITests/CoreFlowTests/testOmradeslistanGarAttSoka
```

UI-testerna tar 15–20 minuter som hel svit. Kör därför bara de UI-tester som rör det som ändrats under arbetet, och hela sviten en gång innan PR:en görs redo eller mergas. Paketets tester och bygget körs varje gång.

## Regler

- Lägsta version är iOS 26. Bas-URL är `https://sopor.hardyson.se/api/v1`.
- User-Agent är `Sophamtning-iOS/<version>`. Varje adress hämtas högst en gång i timmen.
- "I dag" och alla påminnelsetider räknas i `Europe/Stockholm`, oavsett telefonens tidszon.
- Notiser och Live Activities är avstängda från början. Inget schemaläggs utan användarens val.
- Sparade `daysUntil`, `isToday`, `isTomorrow` och `text` visas aldrig. Adress-id tolkas och byggs aldrig om.
- Fraktioner visas alltid med färg, ikon och text. `estimated: true` visas som "ca" överallt.
- Tekniska fel får aldrig se ut som att en adress eller kommun saknas.
- Bundle-id är `se.hardyson.sophamtning`, och App Group är `group.se.hardyson.sophamtning`.
- All text i appen, alla kommentarer och alla commit-meddelanden är på svenska.
- Commit-meddelanden och PR-titlar följer Conventional Commits och har inga AI-attributionsrader. Beskrivningen är på svenska.
  - `feat:` för ny funktion och `fix:` för rättning. Aldrig `feature:`.
  - `docs:`, `test:`, `ci:`, `chore:`, `refactor:` eller `build:` för det som inte ska ge en release, till exempel ändringar i spec och plan (`docs:`).
  - Ändringar som bryter något: `feat!:` och en rad `BREAKING CHANGE:`.

## Releaser

Releaser ska skötas med Release Please (googleapis/release-please-action), med versionstypen `simple`. Flödet byggs i ärende #27 och är inte på plats än.

- Release Please läser commit-meddelandena på `main`: `feat:` höjer minor, `fix:` höjer patch och `!` höjer major. Andra typer ger ingen release och syns inte i changelogen.
- Repot squash-mergar, så PR-titeln blir commit-meddelandet på `main`. Titeln måste därför följa formatet ovan.
- Release Please håller en öppen release-PR med nästa version i `version.txt` och `CHANGELOG.md`. När den mergas skapas taggen `vX.Y.Z` och en GitHub Release.
- Taggen startar bygget till TestFlight. Varje uppladdning godkänns av Jesper, och App Store-inskickning görs bara efter hans godkännande.
- Appens version (`MARKETING_VERSION` i `iOS/project.yml`) ska alltid vara densamma som i `version.txt`. Release Please uppdaterar den. Ändra aldrig version eller changelog för hand.
- Ändringar i specen godkänns av Jesper innan bygget fortsätter.
