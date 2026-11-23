# Hushåll mellan iOS och Android

Status: godkänd av Jesper 2026-11-23 för att skriva planen. Bygget börjar när Android-appen närmar sig.

Bygger på `docs/specs/2026-11-09-hushall.md`. Allt där gäller fortfarande, utom det som den här specen ändrar. Där de säger olika gäller den här.

## Varför

Hushållen bygger i dag på CloudKit, och en Android-användare kan inte vara med i en `CKShare` utan ett Apple-konto och en inloggning via webben. När Android-appen kommer ska en iPhone och en Android-telefon kunna vara i samma hushåll. Det ska kosta så lite som möjligt att driva, helst ingenting.

## Mål

- iPhone och Android kan vara med i samma hushåll, med samma funktioner som i dag: delade adresser, Utställt med Ångra, namn, att gå med, lämna och avsluta, tystad påminnelse och notiser från hushållet.
- Fortfarande inget konto och ingen inloggning.
- Jesper kan inte läsa hushållens innehåll. Adresser, namn och bockar krypteras på telefonerna.
- Driften ryms i Cloudflares gratisnivå för de första tusentals hushållen och blir sedan högst cirka 5 dollar i månaden.
- Befintliga hushåll i CloudKit flyttas automatiskt, utan att någon behöver bjuda in igen.
- Hushållstrafiken kan aldrig påverka Sopor API. Brevlådan ligger på ett eget konto hos Cloudflare, inte på Vercel.

### Inte med

- Android-appens egen implementation. Den här specen beskriver protokollet och iOS-delen. Android följer protokollet i en egen spec.
- Synliga notiser som skickas av servern och dekrypteras i en Notification Service Extension. Det vore säkrare än tyst push, men kommer senare.
- Byte av hushållsnyckeln när någon tas bort (se Säkerhet).
- App Attest och Play Integrity.
- Flera hushåll per person, som förut.

### Får inte hända

- Att ett tekniskt fel, ett nätfel eller en server som inte svarar ser ut som att hushållet, en adress eller en bock saknas, eller som att man har tagits bort.
- Att servern eller Jesper kan se vilka adresser ett hushåll har eller vad deltagarna heter.
- Att någon förlorar sina adresser vid flytten från CloudKit.

## Alternativ som vägdes

| Alternativ | Varför inte |
|---|---|
| CloudKit via webben från Android | Varje Android-användare måste ha ett Apple-konto och logga in i en webbvy. Inloggningen går ut efter två veckor, och CloudKit kan inte skicka push till Android. |
| Vercel med Upstash Redis | Hobby-planens gränser (1 miljon anrop i månaden) delas med Sopor API och de andra projekten på kontot. Nås gränsen stängs allt av i upp till 30 dagar, och appen kan då inte hämta scheman. WebSockets stängs efter 300 sekunder och kostar minne hela tiden de är öppna. |
| Firebase gratis | Lyssnare läser om alla dokument varje gång de startar, så 50 000 läsningar om dagen räcker bara med ett dokument per hushåll. Push kräver ändå en server, eftersom gratisnivån saknar funktioner. Googles SDK i båda apparna. |
| Supabase gratis | Projekt pausas efter en vecka utan aktivitet. |
| **Cloudflare Workers med Durable Objects** | **Valt.** Inga villkor om icke-kommersiellt. Ett objekt med egen SQLite per hushåll. WebSockets som sover utan kostnad, och meddelanden från servern är gratis. 100 000 anrop om dagen gratis, sedan 5 dollar i månaden för 10 miljoner. Egen gräns, skild från Sopor API. |

Jesper valde Cloudflare 2026-11-23, och automatisk flytt av befintliga hushåll (alternativ A) samma dag.

## Översikt

- **Brevlådan:** en Cloudflare Worker i `Server/` i det här repot, skriven i TypeScript. Varje hushåll är ett Durable Object med egen SQLite, låst till EU (`jurisdiction("eu")`). Workern tar emot anropen, kontrollerar behörigheten och skickar vidare till hushållets objekt.
- **Kryptering:** allt innehåll krypteras på telefonen med hushållets nyckel. Nyckeln finns bara i inbjudningslänken och på deltagarnas telefoner. Servern ser hushållets id, deltagarnas id, vem som är ägare, krypterade poster, tidpunkter och push-token.
- **Ändringar till öppna appar:** en WebSocket mot hushållets objekt medan appen är öppen. Servern skickar en signal när något ändras, och appen hämtar ändringarna. Hämtningen var 15:e sekund tas bort.
- **Ändringar till stängda appar:** servern skickar tyst push, via APNs till iPhone och via FCM till Android. Pushen innehåller bara hushållets id och ett löpnummer, aldrig något innehåll.
- **iOS:** en ny `RelayHouseholdSync` implementerar `HouseholdSync`. Logiken och gränssnittet i `SophamtningKit` blir kvar. Under en övergångstid finns också `CloudKitHouseholdSync`, för hushåll som inte har flyttats än.

## Identitet och nycklar

- **Hushåll:** `householdId`, 16 slumpade byte. `householdKey`, 32 slumpade byte, som skapas av den som skapar hushållet och aldrig skickas till servern.
- **Deltagare:** en person i hushållet. `participantId`, 16 slumpade byte som servern skapar. `participantSecret`, 32 slumpade byte som servern skapar och lämnar ut en gång. Servern sparar bara SHA-256 av hemligheten.
- **Enhet:** en telefon som tillhör en deltagare. Den har bara ett eget `deviceId` (16 slumpade byte, skapat på telefonen) och ett push-token.
- **Anrop:** `Authorization: Bearer <participantId>.<participantSecret>`, båda base64url utan utfyllnad.
- **Var nycklarna ligger på iOS:** `householdId`, `householdKey`, `participantId` och `participantSecret` sparas som ett objekt i nyckelringen, synkat med iCloud-nyckelringen (`kSecAttrSynchronizable`) och delat med widgetarna via nyckelringsgruppen för App Group. En person med flera Apple-enheter eller en ny iPhone är då samma deltagare. Push-token och `deviceId` är per enhet och synkas inte.
- **Var nycklarna ligger på Android:** i Block Store, så att de följer med till en ny telefon. Detaljerna står i Android-specen.

Nycklar som härleds från `householdKey` med HKDF-SHA256, utan salt:

| Nyckel | `info` | Används till |
|---|---|---|
| `contentKey` | `sophamtning-hushall-innehall-v1` | AES-256-GCM för posternas innehåll |
| `nameKey` | `sophamtning-hushall-postnamn-v1` | HMAC-SHA256 för postnamnen |

## Inbjudningslänken

```
https://sopor.hardyson.se/hushall#1.<householdId>.<inviteToken>.<householdKey>
```

- Alla delar är base64url utan utfyllnad. `1` är formatets version.
- Allt efter `#` skickas aldrig till någon server när länken öppnas, inte heller till Vercel.
- `inviteToken` är 32 slumpade byte som servern skapar på ägarens begäran. Den gäller i 7 dagar och kan användas av flera personer under den tiden. Servern sparar bara SHA-256 av den.
- Bara ägaren kan skapa inbjudningar, som i dag.
- Länken öppnar appen som Universal Link på iOS och App Link på Android. `sopor.hardyson.se` (Sopor-repot, Vercel) får:
  - `/.well-known/apple-app-site-association` med sökvägen `/hushall` för `se.hardyson.sophamtning`,
  - `/.well-known/assetlinks.json` för Android-appen,
  - sidan `/hushall`, som visas när appen inte är installerad. Den säger att länken är en inbjudan till ett hushåll i Sophämtning och länkar till App Store och Google Play. Sidan läser aldrig delen efter `#`.
- Appen får rättigheten Associated Domains `applinks:sopor.hardyson.se`.

## Posterna

Alla poster i ett hushåll har:

| Fält | Synligt för servern | Innehåll |
|---|---|---|
| `name` | ja | base64url av HMAC-SHA256(`nameKey`, det logiska namnet) |
| `kind` | ja | `address` eller `mark` |
| `data` | nej, krypterat | se nedan |
| `by` | ja | deltagaren som skrev posten, satt av servern |
| `at` | ja | när servern tog emot posten, satt av servern |
| `expiresAt` | ja | bara för `mark`: dagen efter hämtdatumet, 00:00 i `Europe/Stockholm`, som tidpunkt i UTC |

Det logiska namnet är det deterministiska postnamnet från CloudKit-specen: `AddressKey.fileName` för en adress, och `AddressKey.fileName` + `-` + datumet (`yyyy-MM-dd`) för en bock. Det skickas aldrig i klartext, eftersom det innehåller adressens id.

`data` är `nonce || chiffertext || tagg`, base64url, där `nonce` är 12 slumpade byte. Krypteringen är AES-256-GCM med `contentKey`. Tilläggsdatan (AAD) är `householdId`, `name` och `kind`, sammanfogade med `.`, så att en post inte kan flyttas till ett annat namn eller hushåll.

Klartexten är JSON:

- `address`: `{"address": <hela SavedAddress, som i dag>}`. `url` är oförändrad, och adressen eller id:t byggs aldrig om.
- `mark`: `{"source": "...", "id": "...", "date": "yyyy-MM-dd"}`.

Vem som delade en adress eller ställde ut, och när, är fälten `by` och `at` som servern sätter. Klartexten har inga egna sådana fält, eftersom servern inte kan läsa den och därför inte kan kontrollera dem.

Undantaget är poster som har flyttats från CloudKit. De laddas upp av ägaren men kan vara skrivna av någon annan, och klartexten har då också `"legacy": {"by": "<CloudKit-användarens id>", "at": "<ISO 8601>"}`. Appen visar då `legacy.at`, och `legacy.by` översätts till en deltagare via `legacyIds` (nedan). Hittas ingen deltagare med det id:t visas "Någon", som i dag.

Deltagarnas namn är inte poster. Varje deltagare har ett eget krypterat fält `name` hos servern (se Protokollet), med klartexten `{"name": "...", "legacyIds": ["<CloudKit-användarens id>"]}` och AAD `householdId` + `.` + `participantId` + `.name`. `legacyIds` finns bara för den som var med i hushållet i CloudKit.

### Första trycket vinner

- En ny post skrivs med `If-None-Match: *`. Finns namnet redan svarar servern `409` med den befintliga posten, och appen behåller den. Det ersätter `serverRecordChanged` i CloudKit.
- En post skrivs aldrig över. Ändras en delad adress tas den bort och läggs till igen.
- Alla deltagare kan ta bort alla poster, som i dag (Ångra och sluta dela).

## Protokollet

Bas-URL: `https://hushall.sopor.hardyson.se/v1`, som en Custom Domain för Workern. `hardyson.se` hanteras redan av Cloudflare. User-Agent är `Sophamtning-iOS/<version>`, som mot Sopor API.

| Anrop | Vem | Vad |
|---|---|---|
| `POST /households` | vem som helst | Skapar ett hushåll. Svarar med `householdId`, `participantId` och `participantSecret`. Skaparen är ägare. |
| `POST /households/{h}/invites` | ägaren | Body `{"purpose": "invite" \| "migration"}`. Skapar en inbjudan och svarar med `inviteToken` och `expiresAt`. En vanlig inbjudan gäller i 7 dagar. En inbjudan för flytten gäller i 90 dagar och kan bara skapas en gång per hushåll, inom 24 timmar efter att hushållet skapades. |
| `DELETE /households/{h}/invites` | ägaren | Gör alla vanliga inbjudningar ogiltiga. Inbjudan för flytten påverkas inte. |
| `GET /config` | vem som helst | `{"migration": true \| false}`, se Flytten från CloudKit. |
| `POST /households/{h}/join` | den som har en inbjudan | Body `{"inviteToken": "..."}`. Svarar med `participantId` och `participantSecret`. |
| `GET /households/{h}/changes?since={seq}` | deltagare | Allt som ändrats efter löpnumret `seq`, se nedan. `since=0` ger allt. |
| `PUT /households/{h}/records/{name}` | deltagare | Lägger till en post, med `If-None-Match: *`. Body `{"kind", "data", "expiresAt"}`. |
| `DELETE /households/{h}/records/{name}` | deltagare | Tar bort en post. En post som redan är borta ger `204`, inte fel. |
| `PUT /households/{h}/participants/me/name` | deltagare | Body `{"data": "..."}`, mitt krypterade namn. |
| `PUT /households/{h}/participants/me/devices/{deviceId}` | deltagare | Body `{"platform": "apns" \| "fcm", "token": "...", "environment": "production" \| "sandbox"}`. |
| `DELETE /households/{h}/participants/me/devices/{deviceId}` | deltagare | Sluta skicka push till enheten. |
| `DELETE /households/{h}/participants/{p}` | ägaren, eller deltagaren själv | Tar bort en deltagare, eller lämnar när `{p}` är jag. Ägaren kan inte lämna, bara avsluta. |
| `DELETE /households/{h}` | ägaren | Avslutar hushållet. Allt raderas. |
| `GET /households/{h}/socket` | deltagare | WebSocket. Servern skickar `{"seq": n}` när något har ändrats. Appen skickar ingenting. |

Svaret från `changes`:

```json
{
  "seq": 42,
  "full": false,
  "participants": [{"id": "...", "isOwner": true, "joinedAt": "...", "name": "<krypterat eller null>"}],
  "records": [{"name": "...", "kind": "mark", "data": "...", "by": "...", "at": "...", "expiresAt": "..."}],
  "deleted": ["<name>"]
}
```

- `participants` är alltid hela listan.
- `full: true` betyder att `records` är alla poster och att appen ska ersätta sin kopia. Servern svarar så när `since` är 0 eller äldre än det servern minns borttagningar för (30 dagar).
- Löpnumret ökar med varje ändring i hushållet, också när någon går med, lämnar, byter namn eller tas bort.

### Fel

Svaren har formen `{"error": "<kod>"}`. Bara de här koderna får ändra hushållets läge i appen:

| Kod | Status | Appen gör |
|---|---|---|
| `removed` | 403 | Jag är inte längre med. Som att lämna: delade adresser blir kvar som egna, `HouseholdStatus.removed`. |
| `ended` | 410 | Ägaren har avslutat hushållet. Som `removed`. |
| `invite_invalid` | 404 | Inbjudan har gått ut eller gjorts ogiltig: "Inbjudan gäller inte längre. Be om en ny." Gäller också ett hushåll som har avslutats, när man försöker gå med. |
| `full` | 409 | Hushållet har redan 10 deltagare: "Hushållet är fullt." |
| `conflict` | 409 | Posten finns redan. Appen behåller den befintliga. |

Alla andra svar, `5xx`, nätfel och tidsgränser ger `HouseholdStatus.failed` med den senast kända kopian kvar. En `401` (fel hemlighet) är också `failed` och loggas, eftersom den inte bevisar att jag har tagits bort.

Ett hushåll som avslutas eller raderas efter 400 dagar utan aktivitet blir kvar hos servern som en gravsten, för alltid: bara `householdId`, orsaken och tiden. Det är några byte per hushåll. Anrop till hushållet ger då `ended`. Ett hushåll som servern aldrig har känt till ger `{"error": "not_found"}` med status 404, och det är `failed`, aldrig `removed`. Så kan bara servern, inte ett fel, få appen att tro att hushållet är borta. På samma sätt ger en borttagen deltagare `removed` så länge hushållet finns, eftersom servern sparar deltagarens id med tiden för borttagningen.

### Gränser i servern

- Högst 10 deltagare och 200 poster per hushåll, högst 8 kB per post och 512 byte för ett namn.
- Högst 5 nya hushåll per IP-adress och timme. Räknas av ett eget Durable Object per IP-adress, med nyckeln SHA-256 av adressen och dagens datum, så att adressen inte sparas. Cloudflares inbyggda Rate Limiting räknar bara per 10 eller 60 sekunder.
- Bockar raderas av servern när `expiresAt` har passerat (med ett alarm i objektet). Appens `removeExpired` blir kvar, men behövs bara för den lokala kopian.
- Ett hushåll där ingen har gjort något anrop på 400 dagar raderas.
- Servern loggar inga IP-adresser och inga poster utöver det Cloudflare själv loggar.

## Push

- När en bock läggs till, tas bort eller en deltagare går med eller lämnar, skickar servern tyst push till alla andra deltagares enheter. Den som gjorde ändringen får ingen.
- Innehållet är bara `{"h": "<householdId>", "seq": n}`.
- **iPhone:** APNs direkt från Workern, med token-autentisering (JWT med en `.p8`-nyckel), `apns-push-type: background` och `apns-priority: 5`, som CloudKits tysta push i dag. Det första steget i planen är ett försök mot APNs sandbox från en driftsatt Worker. Fungerar det inte används FCM för iPhone också, med Firebase Messaging i iOS-appen.
- **Android:** FCM HTTP v1, med en tjänstekonto-nyckel i Workern.
- Ett push-token som APNs eller FCM säger är ogiltigt tas bort.
- Appen gör som i dag när den väcks: hämtar ändringar och visar lokala notiser enligt valen i arket. iOS garanterar fortfarande inte tyst push, och texten i arket står kvar.

## iOS-appen

### Synken

- `RelayHouseholdSync` implementerar `HouseholdSync` och ligger i `SophamtningKit`, eftersom den bara behöver `URLSession` och CryptoKit. Transporten (HTTP och WebSocket) går via ett protokoll, så att paketets tester kan köras med en falsk server.
- Nyckelringen, Universal Links, registreringen för push och bakgrundsväckningen ligger i appen.
- Den lokala kopian sparas i `LocalStore`, som i dag. Samma regel som `HouseholdSyncTrust` gäller: innan en hämtning med `full: true` har lyckats skickas bara lägen med fel, så att appen aldrig tror att hushållet är tomt.
- Ändringar som inte kan skickas, till exempel utan nät, köas i en fil och skickas vid nästa hämtning. Bocken visas med klockan och **skickas när nätet finns**, som i dag.
- Ändringar hämtas vid start, när appen blir aktiv, vid tyst push, vid bakgrundsuppdateringen och när WebSocketen säger att något har ändrats. WebSocketen är öppen bara när appen är aktiv och jag är med i ett hushåll, och den kopplar upp igen efter 1, 2, 4 och sedan högst 30 sekunder när den bryts.
- Hämtningen var 15:e sekund tas bort.

### Ändringar i det man ser

- **Bjud in till hushållet:** skapar hushållet hos servern, om det inte finns, och en inbjudan. Öppnar sedan delningsarket med länken (`ShareLink`) och texten "Gå med i mitt hushåll i Sophämtning".
- **Gå med:** att öppna länken gör det som att acceptera en `CKShare` gör i dag. Den som redan är med i ett hushåll får först frågan om att lämna det. Raden **Du är med i {ägarens namn}s hushåll** visas sedan som förut.
- **Hantera medlemmar** (`UICloudSharingController`) tas bort. I stället:
  - ägaren kan svepa på en deltagare i arket och välja **Ta bort ur hushållet**, med en bekräftelse,
  - ägaren har knappen **Bjud in fler**, som skapar en ny inbjudan,
  - ägaren har **Gör inbjudningar ogiltiga**, och under den texten "Länkar du har skickat gäller i 7 dagar."
- **Väntar på svar** tas bort, eftersom servern inte vet vem en länk har skickats till. `HouseholdState.invited` blir tom för flyttade hushåll.
- **Ditt namn** fylls inte längre i från Apple-kontot, eftersom det bara kom via CloudKit. Fältet är tomt tills personen skriver något.
- Felen om iCloud (`notSignedIn`, `quotaExceeded`) gäller bara hushåll som inte har flyttats. Ett flyttat hushåll har bara `synced`, `failed` och `removed`.
- Allt annat, korten, Ställ ut kärlen, Ångra, Live Activity, widgeten, raderna om vem som gick med och lämnade, och notiserna, är som i dag.

Ändrade vyer godkänns med skärmbilder i ljust läge, mörkt läge och med största text, som i hushållsspecen.

## Flytten från CloudKit

1. En version av appen har både `CloudKitHouseholdSync` och `RelayHouseholdSync`. Vilken som används avgörs per hushåll: finns nycklar till brevlådan i nyckelringen används den, annars CloudKit.
2. Nya hushåll skapas alltid i brevlådan.
3. **Flytten startar först när servern säger det.** Appen frågar `GET /config` vid start. Bara när svaret är `"migration": true` flyttar ägarens app sitt hushåll. Svarar servern inte, eller med `false`, används CloudKit som förut. Jesper slår på flytten när brevlådan har fungerat för nya hushåll en tid, och kan slå av den igen om något går fel. Ett hushåll som redan har flyttats flyttas inte tillbaka.
4. **Ägaren:** när flytten är på och ägarens app har ett hushåll i CloudKit som inte har flyttats:
   1. Den skapar hushållet i brevlådan, med samma ägare.
   2. Den sparar ägarens namn med `legacyIds` satt till ägarens CloudKit-id.
   3. Den laddar upp alla adresser och alla bockar som inte är förbrukade, också de som andra har skrivit, med `legacy` satt till den ursprungliga avsändaren och tiden.
   4. Den skapar inbjudan för flytten (`"purpose": "migration"`, 90 dagar).
   5. Den skriver posten `HushallFlytt` i CloudKit-zonen, med fältet `link` (hela inbjudningslänken) och `at`.
   6. Från och med nu använder ägarens app bara brevlådan och skriver inte mer i CloudKit.
5. **Medlemmen:** när en medlems app ser `HushallFlytt` i den delade zonen går den med via länken. Den sparar sitt namn med `legacyIds` satt till sitt CloudKit-id och slutar använda CloudKit. Ingen fråga visas, eftersom det är samma hushåll. Medlemmens egna bockar och adresser laddas inte upp igen, eftersom ägaren redan har gjort det.
6. **Inga falska rader om vem som gick med.** En deltagare vars `legacyIds` finns i `HouseholdPreferences.knownParticipants` räknas som redan känd. Det nya id:t läggs till där, och namnet flyttas i `participantNames`. Raden och notisen "{namn} gick med i hushållet" visas inte för den som bara har flyttats. På samma sätt visas inte "{namn} är inte längre med" för det gamla CloudKit-id:t.
7. Avbryts något steg görs det om vid nästa start. Postnamnen är deterministiska, så en adress eller bock som redan har laddats upp ger `conflict` och hoppas över.
8. **Medlemmar med en gammal version** ser hushållet som det var vid flytten tills de uppdaterar. Då går de med automatiskt, så länge inbjudan i `HushallFlytt` gäller.
9. **Efter 90 dagar** tar ägarens app bort `CKShare` och zonen. Medlemmar som inte har uppdaterat då blir kvar med adresserna som egna, enligt regeln för att lämna, och kan bjudas in på nytt.
10. **Ägaren uppdaterar aldrig:** hushållet blir kvar i CloudKit, och medlemmarnas nya appar använder CloudKit-synken för det som förut. Inga Android-användare kan gå med i det.
11. `CloudKitHouseholdSync` tas bort i en senare version, när Jesper bestämmer det.

Länken i `HushallFlytt` innehåller hushållsnyckeln och ligger i iCloud så länge zonen finns. Bara hushållets deltagare kan läsa zonen, men Apple kan i princip läsa den, eftersom delade zoner inte är krypterade från ände till ände.

## Säkerhet

- Servern kan inte läsa adresser, namn eller bockar. Postnamnen är HMAC, så servern kan inte heller se vilka adresser det gäller.
- Servern ser hur många deltagare och poster ett hushåll har, när saker ändras, vem som är ägare och push-token.
- Den som har en länk som fortfarande gäller kan gå med. Därför gäller länkar i 7 dagar och kan göras ogiltiga.
- Den som tas bort kan inte längre hämta något, eftersom servern nekar alla anrop med den deltagarens hemlighet. Personen känner fortfarande till hushållsnyckeln. Utan servern ger det inget, så nyckeln byts inte i den här versionen.
- Hemligheter (`participantSecret`, `inviteToken`) sparas bara som SHA-256 hos servern.

## Integritet

- Integritetspolicyn på https://sopor.hardyson.se/integritet får ett nytt stycke om hushåll: att innehållet krypteras på telefonen och lagras hos Cloudflare i EU, att servern inte kan läsa det, och vilka uppgifter servern ser (se Säkerhet). Cloudflare nämns som personuppgiftsbiträde. Jesper publicerar det innan releasen.
- App Privacy: innehållet räknas troligen inte som insamlat, eftersom Jesper inte kan läsa det. Push-token och deltagar-id sparas däremot läsbart. Jesper avgör före releasen om de ska anges, och `docs/specs/2026-11-06-app-store.md` uppdateras med beslutet.

## Drift

- Jesper skapar ett konto hos Cloudflare. Brevlådan körs på gratisplanen.
- `hardyson.se` hanteras redan av Cloudflare, så `hushall.sopor.hardyson.se` läggs till som Custom Domain för Workern i `wrangler.jsonc`.
- Hemligheterna läggs in med `wrangler secret`: APNs-nyckeln (`.p8`, nyckel-id, team-id) och FCM:s tjänstekonto.
- GitHub Actions driftsätter Workern med `wrangler deploy` när `Server/**` ändras på `main`, med hemligheten `CLOUDFLARE_API_TOKEN`.
- Servern ska inte ge någon release av appen. `release-please-config.json` får `"exclude-paths": ["Server"]` för paketet `.`, så att commits som bara ändrar `Server/` inte höjer appens version och inte syns i appens changelog. Servern har ingen egen version utöver `/v1`.
- Ändringarna på `sopor.hardyson.se` (filerna i `/.well-known/` och sidan `/hushall`) görs i Sopor-repot med en egen PR, som ingår i planen. `assetlinks.json` får Android-appens paketnamn och certifikat när de finns. Till dess innehåller den bara iOS-delen.
- Cloudflares aviseringar säger till när användningen når 70 % av gratisnivån, så att Jesper kan byta till betalplanen i tid.
- Protokollet har version i sökvägen (`/v1`). En ändring som gamla appar inte klarar får en ny version, och den gamla ligger kvar så länge appar använder den.
- `CLAUDE.md` uppdateras: repot har nu en liten egen server i `Server/`, med dess kommandon.

## Test

- **Servern:** Vitest med `@cloudflare/vitest-pool-workers`. Behörighet för varje anrop, första trycket vinner, borttagning av deltagare, att inbjudningar går ut, `full: true` efter 30 dagar, att bockar raderas efter `expiresAt`, gränserna och felkoderna.
- **Testvektorer:** `Server/test/vectors.json` med kända nycklar, postnamn, AAD och chiffertexter. Både paketets tester och Android-appens tester läser samma fil, så att formatet är detsamma på båda plattformarna.
- **Paketet** (Swift Testing, falsk transport): kryptering och postnamn mot testvektorerna, sammanslagning av ändringar, köade ändringar utan nät, att bara felkoderna `removed` och `ended` tar bort hushållet, att `401`, `5xx` och nätfel ger `failed` med kopian kvar, och flyttens steg med en falsk CloudKit-sida.
- **UI-tester:** som i dag, med `InMemoryHouseholdSync`. Nya fall: ta bort en deltagare och gör inbjudningar ogiltiga.
- **Enhet:** fallen i `docs/specs/2026-11-06-enhetschecklista.md` görs om mot brevlådan. Nya fall: flytt av ett befintligt hushåll med två iPhones, en medlem med gammal version, att öppna en länk utan appen installerad, och en ny iPhone som återställs och är samma deltagare. När Android-appen finns: en iPhone och en Android-telefon i samma hushåll.

## Kvar för den som bygger

- Hur filerna i `Server/` delas upp, och hur `RelayHouseholdSync` delas upp i filer.
- Exakt hur länge WebSocketen väntar mellan försöken, inom ramen ovan.
- Hur kön med ändringar som inte har skickats sparas.
- Texterna för de nya felen, inom tonen i hushållsspecen.

## Val som Claude har gjort

Jesper har inte tagit ställning till de här än:

- Koden för servern ligger i det här repot, i `Server/`, så att protokollet och testvektorerna ligger nära båda apparna.
- Inbjudningslänkar gäller i 7 dagar och kan användas av flera, i stället för en länk per person.
- Hushållsnyckeln byts inte när någon tas bort. Servern stänger i stället ute personen.
- En deltagare är en person, och nycklarna synkas med iCloud-nyckelringen, så att en ny iPhone blir samma deltagare.
- APNs direkt från Workern i första hand, och FCM för iPhone bara om det inte fungerar.
- **Väntar på svar** och namnet från Apple-kontot tas bort.
- Inbjudan i `HushallFlytt` gäller i 90 dagar, och sedan tas CloudKit-zonen bort.
- Högst 10 deltagare och 200 poster per hushåll.
- Flytten styrs av `GET /config` och är av från början, så att brevlådan kan provas på nya hushåll först och flytten stängas av om något går fel.
- Ägaren laddar upp också andras bockar och adresser vid flytten, märkta med `legacy`, och CloudKit-id:n översätts via `legacyIds`. Ingen rad om vem som gick med visas för dem som bara flyttats.
- Avslutade och raderade hushåll blir kvar som gravstenar för alltid, så att `ended` aldrig blandas ihop med ett fel.
- Servern ger ingen release av appen (`exclude-paths` i Release Please).
- Sopor-repot ändras i en egen PR som ingår i planen.

## Godkännande

Jesper godkänner specen innan planen skrivs.
