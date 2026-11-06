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
```

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
- Commit-meddelanden följer `feature:` eller `fix:` och har inga AI-attributionsrader.
- Ändringar i specen godkänns av Jesper innan bygget fortsätter.
