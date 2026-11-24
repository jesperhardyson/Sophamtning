# Hushåll mellan iOS och Android

Status: godkänd av Jesper 2026-11-23 för att skriva planen. Utökad 2026-11-24 med Android-appen och push via FCM, som Jesper valde samma dag. Ändringarna från 2026-11-24 väntar på hans godkännande.

Bygger på `docs/specs/2026-11-09-hushall.md`. Allt där gäller fortfarande, utom det som den här specen ändrar. Där de säger olika gäller den här.

## Varför

Hushållen bygger i dag på CloudKit, och en Android-användare kan inte vara med i en `CKShare` utan ett Apple-konto och en inloggning via webben. När Android-appen kommer ska en iPhone och en Android-telefon kunna vara i samma hushåll. Det ska kosta så lite som möjligt att driva, helst ingenting.

## Mål

- iPhone och Android kan vara med i samma hushåll, med samma funktioner som i dag: delade adresser, Utställt med Ångra, namn, att gå med, lämna och avsluta, tystad påminnelse och notiser från hushållet.
- Fortfarande inget konto och ingen inloggning.
- Jesper kan inte läsa hushållens innehåll. Adresser, namn och bockar krypteras på telefonerna.
- Driften ryms i Cloudflares gratisnivå för de första tusentals hushållen och blir sedan cirka 5 dollar i månaden. FCM och Firebase-planen Spark kostar ingenting och kräver inget betalkort.
- Befintliga hushåll i CloudKit flyttas automatiskt, utan att någon behöver bjuda in igen.
- Hushållstrafiken kan aldrig påverka Sopor API. Brevlådan ligger på ett eget konto hos Cloudflare, inte på Vercel.

### Inte med

- Synliga notiser som skickas av servern och dekrypteras i en Notification Service Extension. Det vore säkrare än tyst push, men kommer senare.
- Byte av hushållsnyckeln när någon tas bort (se Säkerhet).
- App Attest och Play Integrity.
- Flera hushåll per person, som förut.
- Firebase utöver Cloud Messaging: ingen Analytics, Crashlytics, databas eller inloggning.

### Får inte hända

- Att ett tekniskt fel, ett nätfel eller en server som inte svarar ser ut som att hushållet, en adress eller en bock saknas, eller som att man har tagits bort.
- Att servern eller Jesper kan se vilka adresser ett hushåll har eller vad deltagarna heter.
- Att någon förlorar sina adresser vid flytten från CloudKit.
- Att en påminnelse på Android uteblir för att hushållet inte gick att hämta.
- Att en telefon registreras hos Firebase utan att personen är med i ett hushåll.

## Alternativ som vägdes

| Alternativ | Varför inte |
|---|---|
| CloudKit via webben från Android | Varje Android-användare måste ha ett Apple-konto och logga in i en webbvy. Inloggningen går ut efter två veckor, och CloudKit kan inte skicka push till Android. |
| Vercel med Upstash Redis | Hobby-planens gränser (1 miljon anrop i månaden) delas med Sopor API och de andra projekten på kontot. Nås gränsen stängs allt av i upp till 30 dagar, och appen kan då inte hämta scheman. WebSockets stängs efter 300 sekunder och kostar minne hela tiden de är öppna. |
| Firebase gratis, som databas | Lyssnare läser om alla dokument varje gång de startar, så 50 000 läsningar om dagen räcker bara med ett dokument per hushåll. Push kräver ändå en server, eftersom gratisnivån saknar funktioner. Googles SDK i båda apparna. |
| Supabase gratis | Projekt pausas efter en vecka utan aktivitet. |
| **Cloudflare Workers med Durable Objects** | **Valt.** Inga villkor om icke-kommersiellt. Ett objekt med egen SQLite per hushåll. WebSockets som sover utan kostnad, och meddelanden från servern är gratis. 100 000 anrop om dagen gratis, sedan 5 dollar i månaden för 10 miljoner. Egen gräns, skild från Sopor API. |

Jesper valde Cloudflare 2026-11-23, och automatisk flytt av befintliga hushåll (alternativ A) samma dag.

**Push till Android:** Jesper valde FCM 2026-11-24. Alternativet utan Firebase hade gett notiserna från hushållet sent eller först när appen öppnas. FCM bryter mot Android-specens regel om bara AndroidX, Jetpack och JetBrains, och `firebase-messaging` blir därför ett uttryckligt undantag där.

## Översikt

- **Brevlådan:** en Cloudflare Worker i `Server/` i det här repot, skriven i TypeScript. Varje hushåll är ett Durable Object med egen SQLite, låst till EU (`jurisdiction("eu")`). Workern tar emot anropen, kontrollerar behörigheten och skickar vidare till hushållets objekt.
- **Kryptering:** allt innehåll krypteras på telefonen med hushållets nyckel. Nyckeln finns bara i inbjudningslänken och på deltagarnas telefoner. Servern ser hushållets id, deltagarnas id, vem som är ägare, krypterade poster, tidpunkter och push-token.
- **Ändringar till öppna appar:** en WebSocket mot hushållets objekt medan appen är öppen. Servern skickar en signal när något ändras, och appen hämtar ändringarna. Hämtningen var 15:e sekund tas bort.
- **Ändringar till stängda appar:** servern skickar tyst push, via APNs till iPhone och via FCM till Android. Pushen innehåller bara hushållets id och ett löpnummer, aldrig något innehåll.
- **iOS och Android** har varsin `RelayHouseholdSync` med samma beteende och samma tester mot en falsk server. På iOS finns den i `SophamtningKit`, på Android i `core`.
- **iOS:** en ny `RelayHouseholdSync` implementerar `HouseholdSync`. Logiken och gränssnittet i `SophamtningKit` blir kvar. Under en övergångstid finns också `CloudKitHouseholdSync`, för hushåll som inte har flyttats än.

## Identitet och nycklar

- **Hushåll:** `householdId`, 16 slumpade byte. `householdKey`, 32 slumpade byte, som skapas av den som skapar hushållet och aldrig skickas till servern.
- **Deltagare:** en person i hushållet. `participantId`, 16 slumpade byte som servern skapar. `participantSecret`, 32 slumpade byte som servern skapar och lämnar ut en gång. Servern sparar bara SHA-256 av hemligheten.
- **Enhet:** en telefon som tillhör en deltagare. Den har bara ett eget `deviceId` (16 slumpade byte, skapat på telefonen) och en push-adress: APNs-tokenet på iPhone och Firebase Installation ID (FID) på Android. FCM:s äldre registreringstoken är på väg bort och används inte. "Push-token" nedan betyder båda.
- **Anrop:** `Authorization: Bearer <participantId>.<participantSecret>`, båda base64url utan utfyllnad.
- **Var nycklarna ligger på iOS:** `householdId`, `householdKey`, `participantId` och `participantSecret` sparas som ett objekt i nyckelringen, synkat med iCloud-nyckelringen (`kSecAttrSynchronizable`) och delat med widgetarna via nyckelringsgruppen för App Group. En person med flera Apple-enheter eller en ny iPhone är då samma deltagare. Push-token och `deviceId` är per enhet och synkas inte.
- **Var nycklarna ligger på Android:** i filen `household-credentials.json` i appens egen katalog, med samma fält. Reglerna för säkerhetskopian tar redan med alla filer, så den följer med till en ny telefon, som då blir samma deltagare. `deviceId` ligger i `household-device.json`, som undantas från säkerhetskopian, liksom Firebase egna filer. Block Store används inte, eftersom det inte behövs.

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
  - sidan `/hushall`, som visas när appen inte är installerad. Den säger också att länken ska öppnas igen när appen är installerad. Den säger att länken är en inbjudan till ett hushåll i Sophämtning och länkar till App Store och Google Play. Sidan läser aldrig delen efter `#`.
- iOS-appen får rättigheten Associated Domains `applinks:sopor.hardyson.se`. Android-appen får ett intent-filter med `autoVerify` för `https://sopor.hardyson.se/hushall`. `assetlinks.json` har SHA-256-fingeravtrycket för Play App Signing (Play Console), inte uppladdningsnyckelns.

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
  - Formatet är det som iOS `JSONEncoder` ger, och Android skriver likadant: alla fält skrivs alltid, utom `detail` som utelämnas när det saknas. `addedAt` är sekunder sedan 1 januari 2001 UTC, som decimaltal.
  - Android måste därför skriva också fält som har sitt standardvärde. `notificationsOn: false` utelämnas annars av `storeJson`, och då kan iOS inte läsa adressen.
  - Okända fält ignoreras av båda.
- `mark`: `{"source": "...", "id": "...", "date": "yyyy-MM-dd"}`.

Vem som delade en adress eller ställde ut, och när, är fälten `by` och `at` som servern sätter. Klartexten har inga egna sådana fält, eftersom servern inte kan läsa den och därför inte kan kontrollera dem.

En post som inte går att dekryptera eller tolka, till exempel från en nyare version, visas inte. Den räknas inte som borttagen: en adress eller bock som redan var känd från samma post står kvar.

Undantaget är poster som har flyttats från CloudKit. De laddas upp av ägaren men kan vara skrivna av någon annan, och klartexten har då också `"legacy": {"by": "<CloudKit-användarens id>", "at": "<ISO 8601>"}`. Appen visar då `legacy.at`, och `legacy.by` översätts till en deltagare via `legacyIds` (nedan). Hittas ingen deltagare med det id:t visas "Någon", som i dag.

Deltagarnas namn är inte poster. Varje deltagare har ett eget krypterat fält `name` hos servern (se Protokollet), med klartexten `{"name": "...", "legacyIds": ["<CloudKit-användarens id>"]}` och AAD `householdId` + `.` + `participantId` + `.name`. `legacyIds` finns bara för den som var med i hushållet i CloudKit.

### Första trycket vinner

- En ny post skrivs med `If-None-Match: *`. Finns namnet redan svarar servern `409` med den befintliga posten, och appen behåller den. Det ersätter `serverRecordChanged` i CloudKit.
- En post skrivs aldrig över. Ändras en delad adress tas den bort och läggs till igen.
- Alla deltagare kan ta bort alla poster, som i dag (Ångra och sluta dela).

## Protokollet

Bas-URL: `https://hushall.sopor.hardyson.se/v1`, som en Custom Domain för Workern. `hardyson.se` hanteras redan av Cloudflare. User-Agent är `Sophamtning-iOS/<version>` och `Sophamtning-Android/<version>`, som mot Sopor API.

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
| `PUT /households/{h}/participants/me/devices/{deviceId}` | deltagare | Body `{"platform": "apns" \| "fcm", "token": "...", "environment": "production" \| "sandbox", "urgent": true \| false}`. För `fcm` är `token` telefonens FID, och `environment` utelämnas. `urgent` betyder att notiserna från hushållet är på och tillåtna, och utelämnat är det `false`. |
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
- Innehållet är bara `{"h": "<householdId>", "seq": n}`. Hos FCM måste alla värden vara text, så `seq` är `"42"` där.
- **iPhone:** APNs direkt från Workern, med token-autentisering (JWT med en `.p8`-nyckel), `apns-push-type: background` och `apns-priority: 5`, som CloudKits tysta push i dag. Det första steget i planen är ett försök mot APNs sandbox från en driftsatt Worker. Fungerar det inte används FCM för iPhone också, med Firebase Messaging i iOS-appen.
- **Android:** FCM HTTP v1 till telefonens FID (`message.fid`), bara `data` och aldrig `notification`, med en tjänstekonto-nyckel i Workern. `collapse_key` är `hushall` och `ttl` ett dygn. Appen hämtar alltid allt sedan sitt `seq`, så det räcker att den sista pushen kommer fram.
  - `priority` är `high` bara när enheten har `urgent` och händelsen ger en notis: en ny bock, eller att någon går med eller lämnar. Google sänker prioriteten för appar vars push med hög prioritet inte leder till en synlig notis. Allt annat är `normal`.
  - `normal` kan dröja när telefonen ligger stilla och vilar (Doze).
- Ett push-token som APNs eller FCM säger är ogiltigt tas bort.
- Appen gör som i dag när den väcks: hämtar ändringar och visar lokala notiser enligt valen i arket. Varken iOS eller Android garanterar att pushen kommer, och texten i arket står kvar på båda.

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
- Texten i det tomma arket säger inte längre att hushållet sparas i iCloud, se Val som Claude har gjort.
- Allt annat, korten, Ställ ut kärlen, Ångra, Live Activity, widgeten, raderna om vem som gick med och lämnade, och notiserna, är som i dag.

Ändrade vyer godkänns med skärmbilder i ljust läge, mörkt läge och med största text, som i hushållsspecen.

## Android-appen

Beteendet är detsamma som på iOS efter den här ändringen. Hushållsspecen och avsnittet ovan är facit, och där de inte säger något är iOS-koden facit. Det som skiljer sig står här.

### Kärnan

- Modellerna, logiken, texterna och hushållsdelen av `AppModel` skrivs om i `core`, med iOS-paketets tester. Inget i `core` känner till Firebase.
- Det finns inget CloudKit på Android, så flytten och valet mellan två synkar finns inte. Android måste däremot läsa `legacy` och `legacyIds` i hushåll som har flyttats från en iPhone.
- Lägena `notSignedIn` och `quotaExceeded` finns inte på Android.
- Kryptering med Javas standardbibliotek (`AES/GCM/NoPadding`, `HmacSHA256`), och HKDF skrivet för hand enligt RFC 5869. HTTP och WebSocket med Ktor, som redan används.
- Synk, kö, felkoder, återuppkoppling och regeln om `full: true` är som på iOS.

### Firebase

- Bara `firebase-messaging` läggs till, och bara i `app`. Google-pluginet och `google-services.json` används inte: de fyra värdena (`google_app_id`, `gcm_defaultSenderId`, `google_api_key` och `project_id`) läggs in som strängresurser när appen byggs, från miljövariabler eller Gradle-egenskaper. De är inga hemligheter och finns i varje installerad app, men repot är publikt och de committas därför inte. API-nyckeln begränsas i Google Cloud till appens paketnamn och signatur.
- Saknas värdena byggs appen utan push, till exempel i PR:er. Releasebygget till Google Play stoppar då i stället.
- Automatisk registrering är avstängd (`firebase_messaging_auto_init_enabled` är `false`). Appen registrerar sig (`FirebaseMessaging.register()`) först när den är med i ett hushåll, och avregistrerar sig och raderar sitt FID när hushållet lämnas eller har avslutats.
- På en telefon utan Google Play-tjänster misslyckas registreringen. Det loggas och visas inte, och allt annat fungerar.
- En push hämtar ändringarna i högst 8 sekunder. Hinner den inte, eller saknas nät, läggs ett engångsarbete i WorkManager som väntar på nätet.

### Tystad påminnelse

En push med `normal` prioritet kan dröja, så Android kontrollerar hushållet en gång till när en påminnelse ska visas. Det går inte på iOS.

- När alarmet för en delad adress går, och **Tysta min påminnelse** är på, hämtas ändringarna i högst 4 sekunder. Har någon ställt ut visas inte påminnelsen.
- Vid fel, utan nät eller när tiden är slut visas påminnelsen som vanligt. När telefonen vilar (Doze) har appen ofta inget nät, så kontrollen är en hjälp men ingen garanti.
- Samma kontroll gäller en påminnelse som visas sent, efter omstart eller när processen startas av alarmet.

### Utseende

- **Inställningar → Delning → Hushåll** öppnar en egen skärm med appfält och bakåtpil, i stället för ett ark.
- **Bjud in till hushållet** och **Bjud in fler** öppnar Androids delningsark med texten "Gå med i mitt hushåll i Sophämtning" och länken.
- En deltagare tas bort från menyn (⋮) på raden, i stället för med svep.
- Frågan om att lämna ett annat hushåll först, och bekräftelserna, är Material-dialoger.
- Notiserna från hushållet har en egen notiskanal, **Hushåll**, med standardvikt. Frågan om notiser ställs bara när **Notiser från hushållet** slås på.
- Widgeten visar **av {namn}** som på iOS. Rutan i snabbinställningarna och Live Update tar hänsyn till hushållets bockar.
- Skärmarna godkänns med skärmbilder i ljust läge, mörkt läge och med största text, som på iOS.

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
- Servern ser hur många deltagare och poster ett hushåll har, när saker ändras, vem som är ägare, push-token och om en Android-telefon har notiserna från hushållet på (`urgent`).
- Google ser att en Android-telefon får push från Sophämtning, och dess FID, hushållets id och löpnumret. Apple ser motsvarande för iPhone. Ingen av dem ser innehållet.
- Nycklarna på Android följer med Googles säkerhetskopia. Den är krypterad från ände till ände när telefonen har ett skärmlås. Utan skärmlås kan Google i princip läsa nycklarna, men inte posterna, som bara finns krypterade hos Cloudflare.
- Den som har en länk som fortfarande gäller kan gå med. Därför gäller länkar i 7 dagar och kan göras ogiltiga.
- Den som tas bort kan inte längre hämta något, eftersom servern nekar alla anrop med den deltagarens hemlighet. Personen känner fortfarande till hushållsnyckeln. Utan servern ger det inget, så nyckeln byts inte i den här versionen.
- Hemligheter (`participantSecret`, `inviteToken`) sparas bara som SHA-256 hos servern.

## Integritet

- Integritetspolicyn på https://sopor.hardyson.se/integritet får ett nytt stycke om hushåll: att innehållet krypteras på telefonen och lagras hos Cloudflare i EU, att servern inte kan läsa det, och vilka uppgifter servern ser (se Säkerhet). Cloudflare nämns som personuppgiftsbiträde, och Google (FCM) för push till Android. Jesper publicerar det innan releasen.
- App Privacy: innehållet räknas troligen inte som insamlat, eftersom Jesper inte kan läsa det. Push-token och deltagar-id sparas däremot läsbart. Jesper avgör före releasen om de ska anges, och `docs/specs/2026-11-06-app-store.md` uppdateras med beslutet.
- Formuläret om datasäkerhet i Google Play: Firebase Installation ID och det som `firebase-messaging` samlar in av sig självt anges, enligt Googles lista för SDK:t. Jesper fyller i det innan en version med hushåll släpps.

## Drift

- Jesper skapar ett konto hos Cloudflare. Brevlådan körs på gratisplanen.
- `hardyson.se` hanteras redan av Cloudflare, så `hushall.sopor.hardyson.se` läggs till som Custom Domain för Workern i `wrangler.jsonc`.
- Jesper skapar ett Firebase-projekt på planen Spark, utan Google Analytics och utan betalkort, med Android-appen `se.hardyson.sophamtning`, och ett tjänstekonto som bara får skicka FCM (rollen Firebase Cloud Messaging API Admin).
- Firebase-värdena till Android-appen ligger som variabler i GitHub-miljön `googleplay`.
- Hemligheterna läggs in med `wrangler secret`: APNs-nyckeln (`.p8`, nyckel-id, team-id) och FCM:s tjänstekonto.
- GitHub Actions driftsätter Workern med `wrangler deploy` när `Server/**` ändras på `main`, med hemligheten `CLOUDFLARE_API_TOKEN`.
- Servern ger ingen release av någon app. Release Please har komponenterna `iOS` och `Android`, och `Server/` ligger utanför båda. Servern har ingen egen version utöver `/v1`.
- **Ordning:** servern driftsätts först, sedan släpps iOS-versionen med brevlådan, och sist Android-versionen med hushåll. Annars kan en Android-användare bjuda in någon vars iPhone-app inte förstår länken.
- Ändringarna på `sopor.hardyson.se` (filerna i `/.well-known/` och sidan `/hushall`) görs i Sopor-repot med en egen PR, som ingår i planen. `assetlinks.json` får Android-appens paketnamn och Play App Signing-fingeravtryck.
- Cloudflares aviseringar säger till när användningen når 70 % av gratisnivån, så att Jesper kan byta till betalplanen i tid.
- Protokollet har version i sökvägen (`/v1`). En ändring som gamla appar inte klarar får en ny version, och den gamla ligger kvar så länge appar använder den.
- `CLAUDE.md` uppdateras: repot har nu en liten egen server i `Server/`, med dess kommandon.

## Test

- **Servern:** Vitest med `@cloudflare/vitest-pool-workers`. Behörighet för varje anrop, första trycket vinner, borttagning av deltagare, att inbjudningar går ut, `full: true` efter 30 dagar, att bockar raderas efter `expiresAt`, gränserna och felkoderna.
- **Testvektorer:** `Server/test/vectors.json` med kända nycklar, postnamn, AAD och chiffertexter. En kopia ligger i iOS-paketets `Fixtures`, som Android redan läser, så att båda apparna testas mot samma fil. CI för servern stoppar om kopian skiljer sig.
- **Paketet** (Swift Testing, falsk transport): kryptering och postnamn mot testvektorerna, sammanslagning av ändringar, köade ändringar utan nät, att bara felkoderna `removed` och `ended` tar bort hushållet, att `401`, `5xx` och nätfel ger `failed` med kopian kvar, och flyttens steg med en falsk CloudKit-sida.
- **`core` på Android:** samma tester som paketet, utom flytten från CloudKit, och att en adress som Android skriver går att läsa på iOS och tvärtom.
- **Android-appen:** att inget registreras hos Firebase utan hushåll, att påminnelsen visas när hämtningen misslyckas, att den tystas när någon har ställt ut, och att `household-device.json` och Firebase filer inte säkerhetskopieras.
- **UI-tester:** som i dag, med `InMemoryHouseholdSync`. Nya fall: ta bort en deltagare och gör inbjudningar ogiltiga.
- **Enhet:** fallen i `docs/specs/2026-11-06-enhetschecklista.md` görs om mot brevlådan. Nya fall: flytt av ett befintligt hushåll med två iPhones, en medlem med gammal version, att öppna en länk utan appen installerad, och en ny iPhone som återställs och är samma deltagare. En iPhone och en Android-telefon i samma hushåll, åt båda hållen: bjuda in, dela en adress, ställa ut och ångra, notis och tystad påminnelse. En Android-telefon som legat stilla (Doze), och en ny Android-telefon som återställs.

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
- Sopor-repot ändras i en egen PR som ingår i planen.

Tillagda 2026-11-24, med Android:

- FCM med FID i stället för den äldre registreringstoken, och utan Google-pluginet och `google-services.json`.
- Fältet `urgent`, så att hög prioritet bara används när pushen ger en notis.
- Registrering hos Firebase först när personen är med i ett hushåll.
- Kontrollen av hushållet precis innan en påminnelse visas på Android.
- Nycklarna på Android i en vanlig fil som följer med säkerhetskopian.
- En deltagare tas bort från radens meny på Android, och hushållet är en skärm i stället för ett ark.
- Texten i det tomma arket, som i dag säger "Hushållet sparas i ert iCloud.", ändras på båda plattformarna till "Hushållet krypteras på era telefoner, och bara ni kan läsa det.".

## Godkännande

Jesper godkände specen 2026-11-23. Ändringarna från 2026-11-24 godkänns innan bygget börjar.
