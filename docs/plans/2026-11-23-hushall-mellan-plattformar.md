# Hushåll mellan iOS och Android: plan för servern och iOS

> **För agenter:** Använd superpowers:subagent-driven-development eller superpowers:executing-plans, en uppgift i taget. Stegen har kryssrutor (`- [ ]`).

**Mål:** Hushållen flyttar från CloudKit till en krypterad brevlåda på Cloudflare, så att en Android-telefon kan vara med i samma hushåll som en iPhone. Befintliga hushåll flyttas automatiskt.

**Upplägg:** Servern är en Cloudflare Worker i `Server/` med ett Durable Object (SQLite, EU) per hushåll. Den ser bara krypterade poster. I iOS-appen ligger allt som går att testa i `SophamtningKit`: kryptering, protokollet, `RelayHouseholdSync`, flytten och valet mellan brevlåda och CloudKit. Det testas mot en falsk server i paketet. Appen har bara nyckelringen, HTTP och WebSocket, push, Universal Links och vyerna. Arbetet görs på grenen `feature/hushall-mellan-plattformar`, i tre PR:er: servern (uppgift 1–3), iOS-appen (4–10) och Sopor-repot (11).

**Teknik:**
- Servern: TypeScript, Cloudflare Workers, Durable Objects med SQLite, Wrangler, Vitest med `@cloudflare/vitest-pool-workers`.
- iOS: Swift 6, SwiftUI, CryptoKit, `URLSessionWebSocketTask`, Security (nyckelringen), Swift Testing, XCTest, xcodegen.

**Spec:** `docs/specs/2026-11-23-hushall-mellan-plattformar.md`. Den bygger på `docs/specs/2026-11-09-hushall.md`, och båda ska läsas.

**Ordning:** 0, 1, 2, 3, sedan 4–10, och 11 när 8 behöver länkarna. Servern (1–3) kan driftsättas innan iOS-delen börjar. Android-appen har en egen plan, `docs/plans/2026-11-24-android-hushall.md`, som kan börja när uppgift 3 och 4 är klara.

## Gemensamma krav

- Lägsta version är iOS 26. Inga tredjepartsbibliotek i iOS-appen. Servern får bara ha utvecklingsberoenden (`wrangler`, `vitest`, `@cloudflare/vitest-pool-workers`, `typescript`).
- All text i appen, alla kommentarer och alla commit-meddelanden är på svenska. Inga AI-attributionsrader. Commits följer Conventional Commits.
- Bas-URL för brevlådan: `https://hushall.sopor.hardyson.se/v1`. User-Agent: `Sophamtning-iOS/<version>`, och `Sophamtning-Android/<version>` i Android-planen.
- Durable Objects skapas med `env.HOUSEHOLD.jurisdiction("eu")`.
- Kryptering: AES-256-GCM med 12 byte slumpad nonce. `data` = base64url(`nonce || chiffertext || tagg`). AAD för poster: `householdId + "." + name + "." + kind`. AAD för namn: `householdId + "." + participantId + ".name"`.
- HKDF-SHA256 utan salt från `householdKey`: `contentKey` med info `sophamtning-hushall-innehall-v1`, `nameKey` med info `sophamtning-hushall-postnamn-v1`. Postnamn = base64url(HMAC-SHA256(`nameKey`, logiskt namn)).
- Allt base64url är utan utfyllnad.
- Länk: `https://sopor.hardyson.se/hushall#1.<householdId>.<inviteToken>.<householdKey>`.
- Gränser: 10 deltagare, 200 poster, 8 kB per post, 512 byte per namn, 20 nya hushåll per IP-adress och timme. Vanlig inbjudan gäller 7 dagar, inbjudan för flytten 90 dagar. Borttagningar sparas i 30 dagar. Ett hushåll utan anrop på 400 dagar raderas.
- Bara felkoderna `removed` och `ended` får ta bort hushållet i appen. Allt annat är `HouseholdStatus.failed` med kopian kvar.
- "I dag", hämtdatum och `expiresAt` räknas i `Europe/Stockholm` (`StockholmClock`, `DayDate`).
- Adress-id tolkas och byggs aldrig om. `SavedAddress.url` krypteras och används oförändrad.
- Varje uppgift kör det som rör den:
  - `cd Server && npm test` för servern.
  - `cd iOS/Packages/SophamtningKit && swift test` och bygget för iOS.
  - UI-tester bara för det som ändras, och hela sviten en gång innan iOS-PR:en görs redo.

## Fokus vid granskning

1. **Servern svarar 500 eller inte alls när appen startar.** Delade adresser och bockar står kvar från kopian med "Hushållet kunde inte uppdateras just nu", och inget tas bort. Testet `serverFelBehallerHushallet` i uppgift 5.
2. **Två telefoner bockar samma hämtning utan nät och kommer online efter varandra.** Den första hos servern vinner. Den andra visar den förstas namn och tid, och ingen får två notiser. Testet `sammaBockFranTvaTelefonerForstaVinner` i uppgift 5.
3. **Länken till hushållet man redan är med i öppnas igen.** Ingen fråga om att lämna, bara en hämtning. Testet `lankTillSammaHushallFragarInte` i uppgift 9.
4. **Flytten avbryts efter att hushållet skapats i brevlådan men innan `HushallFlytt` skrivits.** Vid nästa start fortsätter flytten i samma hushåll, och det blir inget nytt. Testet `avbrutenFlyttFortsatterISammaHushall` i uppgift 6.
5. **En ny iPhone återställs med nycklarna från iCloud-nyckelringen.** Den blir samma deltagare och registrerar sitt eget push-token. Det gamla tokenet tas bort när APNs svarar 410. Testerna `nyEnhetSammaDeltagare` i uppgift 5 och `ogiltigtTokenTasBort` i uppgift 3.

## Filer

| Fil | Ansvar |
|---|---|
| `Server/wrangler.jsonc` | Workern, bindningarna `HOUSEHOLD` och `LIMITER`, Custom Domain, SQLite-migrering |
| `Server/src/index.ts` | Routning, behörighet, vidarebefordran till rätt objekt |
| `Server/src/household.ts` | `class Household extends DurableObject`: tabeller, anrop, seq, alarm, WebSocket |
| `Server/src/limiter.ts` | `class CreationLimiter extends DurableObject`: 20 nya hushåll per IP och timme |
| `Server/src/push.ts` | APNs med JWT och FCM HTTP v1 |
| `Server/src/encoding.ts` | base64url, slumpade byte, SHA-256 |
| `Server/test/*.test.ts` | Serverns tester |
| `Server/test/vectors.json` | Testvektorer för krypteringen, delas med iOS och Android |
| `.github/workflows/server.yml` | Test och `wrangler deploy` |
| `SophamtningKit/Household/Relay/HouseholdCrypto.swift` | Nycklar, postnamn, kryptering |
| `SophamtningKit/Household/Relay/HouseholdInviteLink.swift` | Länken till och från `URL` |
| `SophamtningKit/Household/Relay/RelayWire.swift` | JSON-typerna i protokollet och felkoderna |
| `SophamtningKit/Household/Relay/RelayTransport.swift` | Protokollet för HTTP och signaler |
| `SophamtningKit/Household/Relay/RelayHouseholdSync.swift` | `HouseholdSync` och `HouseholdMembership` mot brevlådan |
| `SophamtningKit/Household/Relay/RelayPendingQueue.swift` | Kön med ändringar som inte har skickats |
| `SophamtningKit/Household/HouseholdMembership.swift` | Protokollet för inbjudan, gå med, ta bort och avsluta |
| `SophamtningKit/Household/HouseholdMigrator.swift` | Flytten från CloudKit |
| `SophamtningKit/Household/RoutingHouseholdSync.swift` | Väljer brevlådan eller CloudKit per hushåll |
| `SophamtningKit/Household/HouseholdModels.swift` | `HouseholdParticipant.legacyIds` |
| `SophamtningKit/Household/HouseholdLogic.swift` | Kända deltagare via `legacyIds`. `liveFetchInterval` tas bort |
| `SophamtningKit/Household/HouseholdTexts.swift` | De nya texterna |
| `SophamtningKit/App/AppModel+Household.swift` | Inbjudan, ta bort, avsluta, länken |
| `iOS/Sophamtning/Household/KeychainCredentialStore.swift` | Nycklarna i nyckelringen |
| `iOS/Sophamtning/Household/URLSessionRelayTransport.swift` | HTTP och WebSocket |
| `iOS/Sophamtning/Household/HouseholdLinkAcceptance.swift` | Tar emot länken |
| `iOS/Sophamtning/Household/CloudKitHouseholdSync+Legacy.swift` | `LegacyHousehold` för flytten |
| `iOS/Sophamtning/Views/HouseholdSheet.swift` | Deltagarlistan, inbjudan, ta bort |
| `iOS/project.yml` | Associated Domains, nyckelringsgrupp |

Sökvägar som börjar med `SophamtningKit/` ligger under `iOS/Packages/SophamtningKit/Sources/`, och testerna under `iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/`.

---

## Uppgift 0: Förberedelser och försök med APNs och FCM

Den största risken är att APNs inte går att nå från en driftsatt Worker, och sedan att signeringen för FCM inte ryms i gratisplanens 10 ms processortid. Båda prövas först, med kod som slängs.

**Jesper gör:**
- [ ] Skapar en APNs-nyckel (`.p8`) i Apple Developer under Certificates, Identifiers & Profiles > Keys, med Apple Push Notifications service. Noterar nyckel-id och team-id.
- [ ] Skapar en API-token i Cloudflare med behörigheten Workers Scripts: Edit och Workers Routes för zonen `hardyson.se`. Lägger in den som GitHub-hemligheten `CLOUDFLARE_API_TOKEN`, och konto-id:t som `CLOUDFLARE_ACCOUNT_ID`.
- [ ] Skapar ett Firebase-projekt på Spark, utan Google Analytics och utan betalkort, med Android-appen `se.hardyson.sophamtning`. Skapar ett tjänstekonto med rollen Firebase Cloud Messaging API Admin och laddar ner dess JSON-nyckel. Nyckeln läggs aldrig i repot.

**Försöket:**
- [ ] **Steg 1:** Skapa en Worker utanför repot (`/tmp`, eller scratchpad) som signerar en JWT med ES256 (`crypto.subtle`, nyckeln från `.p8`). Den skickar `POST https://api.sandbox.push.apple.com/3/device/<token>` med `apns-push-type: background`, `apns-priority: 5`, `apns-topic: se.hardyson.sophamtning` och body `{"aps":{"content-available":1},"h":"test","seq":1}`.
- [ ] **Steg 2:** Ta ett push-token från ett utvecklingsbygge på Jespers iPhone (logga det i `didRegisterForRemoteNotificationsWithDeviceToken`). Driftsätt med `wrangler deploy` och anropa.
- [ ] **Steg 3:** Klart när APNs svarar `200`, och appen väcks (loggen i `didReceiveRemoteNotification`).
- [ ] **Steg 4:** Fungerar det inte efter rimliga försök: stoppa och fråga Jesper. Då gäller specens reserv, FCM också för iPhone, och det kräver att planen ändras (Firebase Messaging bryter mot "inga tredjepartsbibliotek" på iOS, och undantaget gäller bara Android).
- [ ] **Steg 5:** FCM: låt samma Worker signera en JWT med RS256 (tjänstekontots nyckel), byta den mot en åtkomsttoken hos `https://oauth2.googleapis.com/token` (scope `https://www.googleapis.com/auth/firebase.messaging`) och skicka `POST https://fcm.googleapis.com/v1/projects/<projekt>/messages:send` med `"validate_only": true` och ett påhittat `fid`. Klart när svaret är FCM:s eget fel om ett ogiltigt `fid` och inte `401` eller `403`. Läs processortiden i Cloudflares loggar.
- [ ] **Steg 6:** Är processortiden över 8 ms: flytta signeringen till hushållets Durable Object, där gränsen är högre, och mät igen. Är den fortfarande för hög: stoppa och fråga Jesper (betalplanen kostar 5 dollar i månaden).
- [ ] **Steg 7:** Skriv resultaten under Uppgift 0 i den här planen och committa: `docs: Resultat av försöken med APNs och FCM från Cloudflare`.

---

## Uppgift 1: Servern: hushåll, deltagare och inbjudningar

**Files:**
- Create: `Server/package.json`, `Server/tsconfig.json`, `Server/wrangler.jsonc`, `Server/vitest.config.ts`, `Server/src/index.ts`, `Server/src/household.ts`, `Server/src/limiter.ts`, `Server/src/encoding.ts`
- Test: `Server/test/households.test.ts`

**Interfaces:**
- Produces:
  - `export class Household extends DurableObject<Env>` med metoden `fetch(request: Request): Promise<Response>`, som tar emot anrop som redan har passerat routningen, med huvudet `X-Participant` satt när anropet har en giltig hemlighet.
  - `export class CreationLimiter extends DurableObject<Env>` med `allow(): Promise<boolean>`.
  - `encoding.ts`: `b64url(bytes: Uint8Array): string`, `fromB64url(s: string): Uint8Array`, `randomB64url(n: number): string`, `sha256B64url(s: string): Promise<string>`.
  - Tabeller i `Household` (SQLite):
    - `meta(key TEXT PRIMARY KEY, value TEXT)` med nycklarna `householdId`, `createdAt`, `lastActivity`, `seq`, `endedAt`, `endedReason` och `migrationInviteAt`.
    - `participants(id TEXT PRIMARY KEY, secretHash TEXT, isOwner INTEGER, joinedAt TEXT, removedAt TEXT, nameData TEXT)`.
    - `invites(tokenHash TEXT PRIMARY KEY, purpose TEXT, expiresAt TEXT)`.

- [ ] **Steg 1: Skriv tester som misslyckas** i `Server/test/households.test.ts`:
  - `skaparHushallMedAgare`: `POST /v1/households` ger `201` med `householdId` (22 tecken), `participantId` och `participantSecret`. `GET /v1/households/{h}/changes?since=0` med den hemligheten ger `200`, `full: true` och en deltagare med `isOwner: true`.
  - `felHemlighetGer401`
  - `inbjudanGallerSjuDagar`: `expiresAt` är 7 dagar fram. Den som går med med inbjudan får `201`. Efter 7 dagar och en sekund (`vi.setSystemTime`) ger den `404` och `invite_invalid`.
  - `baraAgarenBjuderIn`: en medlem får `403` på `POST /invites`.
  - `flyttinbjudanBaraEnGangOchInomEttDygn`: `purpose: "migration"` ger 90 dagar. En andra gång ger `409`, och efter 24 timmar också `409`.
  - `ogiltigforklaringRorInteFlytten`: `DELETE /invites` gör vanliga inbjudningar ogiltiga men inte den för flytten.
  - `elvaDeltagareGerFull`: den elfte som går med får `409` och `full`.
  - `borttagenDeltagareGerRemoved`: ägaren tar bort en medlem, och medlemmens anrop ger `403` och `removed`. Medlemmen kan lämna själv på samma sätt.
  - `agarenKanInteLamna`: `DELETE /participants/<ägaren>` av ägaren själv ger `409`.
  - `avslutatHushallGerEnded`: efter `DELETE /households/{h}` ger alla anrop `410` och `ended`, och `join` ger `invite_invalid`.
  - `okantHushallGerNotFound`: ett slumpat id ger `404` och `not_found`.
  - `sexteHushalletFranSammaIpNekas`: med `CF-Connecting-IP` satt ger det sjätte inom en timme `429`.
- [ ] **Steg 2:** Kör `cd Server && npm install && npm test`. Förväntat: testerna misslyckas.
- [ ] **Steg 3:** Implementera. Hemligheter jämförs som SHA-256. `householdId` och `participantId` är `randomB64url(16)`, hemligheter `randomB64url(32)`. Routningen i `index.ts` hämtar objektet med `env.HOUSEHOLD.jurisdiction("eu").idFromName(householdId)`. En gravsten är att `endedAt` är satt och alla andra tabeller är tömda. `CreationLimiter` nås med `idFromName(sha256(ip + dagens datum))`.
- [ ] **Steg 4:** Kör `npm test`. Förväntat: alla gröna.
- [ ] **Steg 5:** Committa: `feat: Brevlådan för hushåll skapar hushåll och tar emot deltagare`

## Uppgift 2: Servern: poster, ändringar och städning

**Files:**
- Modify: `Server/src/household.ts`
- Test: `Server/test/records.test.ts`

**Interfaces:**
- Consumes: `Household` och tabellerna från uppgift 1.
- Produces:
  - Tabellerna `records(name TEXT PRIMARY KEY, kind TEXT, data TEXT, by TEXT, at TEXT, expiresAt TEXT, seq INTEGER)` och `deletions(name TEXT PRIMARY KEY, seq INTEGER, at TEXT)`.
  - Svaret från `changes` exakt enligt specen.
  - `seq` ökar med 1 för varje ändring av poster, deltagare och namn.

- [ ] **Steg 1: Skriv tester som misslyckas:**
  - `forstaSkrivningenVinner`: två `PUT` med `If-None-Match: *` och samma namn. Den andra ger `409` och `conflict`, med den första postens `data`, `by` och `at` i svaret.
  - `putUtanIfNoneMatchGer428`
  - `bySattesAvServern`: `by` är avsändarens `participantId`, vad klienten än skickar.
  - `changesSinceGerBaraNytt`: efter `seq` 3 ger `since=3` bara det som ändrats sedan, och borttagna namn i `deleted`.
  - `gammalSinceGerFull`: borttagningar äldre än 30 dagar rensas, och `since` före det ger `full: true`.
  - `taBortSaknadPostGer204`
  - `namnSyns`: `PUT /participants/me/name` syns i `participants[].name` och ökar `seq`.
  - `bockRaderasEfterExpiresAt`: alarmet tar bort posten efter `expiresAt` och lägger den i `deletions`.
  - `grans200Poster` och `grans8kB`: ger `413`. `grans512ByteNamn` på samma sätt för namnet.
  - `hushallRaderasEfter400Dagar`: utan anrop i 400 dagar blir hushållet en gravsten med `endedReason: "inactive"`.
- [ ] **Steg 2:** Kör `npm test`. Förväntat: de nya testerna misslyckas.
- [ ] **Steg 3:** Implementera. Varje anrop uppdaterar `lastActivity` och sätter om alarmet till det tidigaste av nästa `expiresAt`, 400 dagar fram och nästa rensning av `deletions`.
- [ ] **Steg 4:** Kör `npm test`. Förväntat: alla gröna.
- [ ] **Steg 5:** Committa: `feat: Brevlådan sparar poster och ger ändringar`

## Uppgift 3: Servern: signaler, push, config och driftsättning

**Files:**
- Create: `Server/src/push.ts`, `.github/workflows/server.yml`
- Modify: `Server/src/household.ts`, `Server/src/index.ts`
- Test: `Server/test/push.test.ts`, `Server/test/socket.test.ts`

**Interfaces:**
- Consumes: uppgift 1 och 2.
- Produces:
  - Tabellen `devices(deviceId TEXT PRIMARY KEY, participantId TEXT, platform TEXT, token TEXT, environment TEXT, urgent INTEGER)`.
  - `push.ts`:
    - `sendApns(env: Env, token: string, environment: "production" | "sandbox", payload: {h: string, seq: number}): Promise<"ok" | "invalid" | "error">`
    - `sendFcm(env: Env, fid: string, priority: "high" | "normal", payload: {h: string, seq: number}): Promise<"ok" | "invalid" | "error">`
  - `GET /v1/config` svarar `{"migration": <env.MIGRATION === "on">}`.
  - Hemligheter i `Env`: `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `FCM_SERVICE_ACCOUNT`. Variabel: `MIGRATION`.

- [ ] **Steg 1: Skriv tester som misslyckas** (APNs och FCM via `fetchMock`):
  - `bockGerPushTillAndra`: en ny `mark` ger ett anrop till APNs för medlemmens enhet och inget för avsändarens. Body är `{"aps":{"content-available":1},"h":"<h>","seq":<n>}`.
  - `fcmSkickarBaraData`: en enhet med `platform: "fcm"` får `POST .../messages:send` med exakt `{"message":{"fid":"<token>","data":{"h":"<h>","seq":"<n>"},"android":{"priority":"normal","collapse_key":"hushall","ttl":"86400s"}}}`. Det finns inget `notification`.
  - `hogPrioritetBaraNarNotisenSyns`: med `urgent: true` ger en ny bock, någon som går med och någon som lämnar `"priority":"high"`. En bock som tas bort ger `"normal"`. Med `urgent: false` eller utelämnat är allt `"normal"`.
  - `ettFelForEnEnhetStopparInteDeAndra`: FCM svarar `500` för en enhet, och de andra får sin push. Enheten finns kvar.
  - `adressGerIngenPush`: en ny `address` ger ingen push, men en signal på WebSocketen.
  - `ogiltigtTokenTasBort`: APNs svarar `410` (eller FCM `404` med `UNREGISTERED`), och enheten försvinner ur `devices`. FCM `400` med `INVALID_ARGUMENT` tar inte bort den, eftersom det kan vara ett fel i vårt anrop.
  - `socketFarSeq`: en öppen WebSocket får `{"seq":n}` efter en ändring, och Hibernation API används (`ctx.acceptWebSocket`).
  - `socketKraverDeltagare`: utan giltig hemlighet ger uppkopplingen `401`.
  - `taBortEnhetStopparPush`: efter `DELETE /participants/me/devices/{deviceId}` får enheten ingen push.
  - `configFoljerVariabeln`
- [ ] **Steg 2:** Kör `npm test`. Förväntat: de nya testerna misslyckas.
- [ ] **Steg 3:** Implementera. Push skickas efter svaret med `ctx.waitUntil`. APNs-JWT:n sparas i minnet i högst 50 minuter, och FCM:s OAuth-token tills den har gått ut. Vilka händelser som ger push är specens: en bock läggs till eller tas bort, och en deltagare går med eller lämnar. Varje ändring ger en signal på WebSocketen.
- [ ] **Steg 4:** `release-please-config.json` ändras inte: `Server/` ligger utanför komponenterna `iOS` och `Android`. Skapa `.github/workflows/server.yml`: på PR som ändrar `Server/**` körs `npm ci && npm test`, och på push till `main` som ändrar `Server/**` också `npx wrangler deploy` med `CLOUDFLARE_API_TOKEN` och `CLOUDFLARE_ACCOUNT_ID`. Följ stilen i `.github/workflows/release.yml` med åtgärder låsta till commit-hash.
- [ ] **Steg 5:** Skriv `Server/test/vectors.json` med fem fall, med fast nyckel och fast nonce:
  - en adress med alla fält, med å, ä och ö och en procentkodad `url`
  - en adress utan `detail`, skriven som iOS `JSONEncoder` skriver den, med `\/` i `url` och ett okänt fält `"framtida": 1`
  - en bock
  - en flyttad bock med `legacy`
  - ett namn med `legacyIds`

  Varje fall har `householdKey`, `householdId`, `logical`, `name`, `kind`, `nonce`, `plaintext` och `data`. Räkna fram värdena med WebCrypto i ett testskript som ligger kvar som `Server/test/vectors.test.ts`, så att de kontrolleras varje gång.
- [ ] **Steg 6:** Kör `npm test`. Förväntat: alla gröna.
- [ ] **Steg 7:** Lägg in hemligheterna med `npx wrangler secret put` (Jesper, med nyckeln från uppgift 0). Driftsätt och kontrollera att `curl https://hushall.sopor.hardyson.se/v1/config` ger `{"migration":false}`.
- [ ] **Steg 8:** Committa: `feat: Brevlådan skickar push och driftsätts från GitHub`. Gör PR:en för servern.

---

## Uppgift 4: Kryptering och länken i paketet

**Files:**
- Create: `SophamtningKit/Household/Relay/HouseholdCrypto.swift`, `SophamtningKit/Household/Relay/HouseholdInviteLink.swift`
- Create: `Tests/SophamtningKitTests/Fixtures/hushall-vectors.json`, en kopia av `Server/test/vectors.json`, läst på samma sätt som de andra filerna i Fixtures. Android läser samma kopia.
- Modify: `.github/workflows/server.yml`: steget `cmp Server/test/vectors.json iOS/Packages/SophamtningKit/Tests/SophamtningKitTests/Fixtures/hushall-vectors.json`, så att en ändring i bara den ena stoppas
- Test: `HouseholdCryptoTests.swift`, `HouseholdInviteLinkTests.swift`

**Interfaces:**
- Produces:
  - `public enum RelayRecordKind: String, Codable, Sendable { case address, mark }`
  - `public struct HouseholdCrypto: Sendable`:
    - `init(householdId: String, householdKey: Data)`
    - `func recordName(_ logical: String) -> String`
    - `func seal(_ plaintext: Data, name: String, kind: RelayRecordKind) throws -> String`
    - `func open(_ data: String, name: String, kind: RelayRecordKind) throws -> Data`
    - `func sealName(_ plaintext: Data, participantId: String) throws -> String`
    - `func openName(_ data: String, participantId: String) throws -> Data`
    - `static func newKey() -> Data`
    - En intern `seal(..., nonce:)` för testerna.
  - `public struct HouseholdInviteLink: Hashable, Sendable`:
    - fälten `householdId`, `inviteToken` och `householdKey: Data`
    - `init?(url: URL)`
    - `var url: URL`

- [ ] **Steg 1: Skriv tester som misslyckas:**
  - `vektorernaStammer`: alla fall i `hushall-vectors.json` ger exakt `name` och `data`, och `open` ger tillbaka `plaintext`.
  - `vektorfilenArSammaSomServerns`: filen i Fixtures är byte för byte lika med `Server/test/vectors.json` (sökvägen relativt `#filePath`).
  - `adresserFranVektorernaGarAttLasa`: båda adressfallen avkodas till `SavedAddress` med oförändrad `url.absoluteString`, och det okända fältet ignoreras.
  - `felAADGerFel`: `open` med ett annat `name` eller `kind` kastar.
  - `lankTillOchFran`: en länk blir samma värde efter `url` och `init?(url:)`, och `url.absoluteString` börjar med `https://sopor.hardyson.se/hushall#1.`
  - `lankMedFelVersionEllerVardEllerDelarGerNil`: `#2.…`, fel värd, fyra delar istället för fem och en nyckel som inte är 32 byte ger `nil`.
- [ ] **Steg 2:** Kör `swift test --filter HouseholdCrypto` och `--filter HouseholdInviteLink`. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera med CryptoKit (`HKDF<SHA256>`, `HMAC<SHA256>`, `AES.GCM`).
- [ ] **Steg 4:** Kör `swift test`. Förväntat: alla gröna.
- [ ] **Steg 5:** Committa: `feat: Kryptering och länk för hushåll i brevlådan`

## Uppgift 5: `RelayHouseholdSync` mot en falsk server

**Files:**
- Create: `SophamtningKit/Household/Relay/RelayWire.swift`, `RelayTransport.swift`, `RelayHouseholdSync.swift`, `RelayPendingQueue.swift`, `SophamtningKit/Household/HouseholdMembership.swift`
- Create (test): `FakeRelayServer.swift`, `RelayHouseholdSyncTests.swift`
- Modify: `SophamtningKit/Household/HouseholdModels.swift`

**Interfaces:**
- Consumes: `HouseholdCrypto` och `HouseholdInviteLink` (uppgift 4), `HouseholdSync`, `HouseholdState` och `LocalStore`.
- Produces:
  - `public struct HouseholdCredentials: Codable, Hashable, Sendable` med `householdId`, `householdKey: Data`, `participantId` och `participantSecret`.
  - `public protocol HouseholdCredentialStore: Sendable` med `load() -> HouseholdCredentials?`, `save(_: HouseholdCredentials) throws` och `delete() throws`. `InMemoryCredentialStore` för tester.
  - `public struct RelayRequest: Sendable` med `method`, `path`, `headers: [String: String]` och `body: Data?`. `public struct RelayResponse: Sendable` med `status: Int` och `body: Data`.
  - `public protocol RelayTransport: Sendable`:
    - `func send(_ request: RelayRequest) async throws -> RelayResponse`
    - `func signals(householdId: String, authorization: String) -> AsyncStream<Int>`
  - `public enum RelayErrorCode: String, Codable { case removed, ended, inviteInvalid = "invite_invalid", full, conflict, notFound = "not_found" }`
  - `public protocol HouseholdMembership: AnyObject, Sendable`:
    - `func create(myName: String) async throws`
    - `func invite() async throws -> URL`
    - `func revokeInvites() async throws`
    - `func join(_ link: HouseholdInviteLink, myName: String?) async throws`
    - `func remove(participantId: String) async throws`
    - `func end() async throws`
    - `func registerDevice(token: String, environment: String) async`
    - `func isCurrent(_ link: HouseholdInviteLink) -> Bool`
  - `public final class RelayHouseholdSync: HouseholdSync, HouseholdMembership`:
    - `init(transport: any RelayTransport, credentials: any HouseholdCredentialStore, store: LocalStore, now: @escaping @Sendable () -> Date = { Date() })`
    - `public var hasHousehold: Bool`
    - `func startSignals()`, `func stopSignals()`
  - `HouseholdParticipant.legacyIds: [String]`, standard `[]`. Saknas fältet i en äldre fil blir det `[]`.
  - Filerna i `LocalStore`: `household-relay.json` (kopian med `seq`) och `household-relay-pending.json` (kön).
  - `InMemoryHouseholdSync` implementerar också `HouseholdMembership`, för UI-testerna.

- [ ] **Steg 1:** Skriv `FakeRelayServer: RelayTransport` i testerna. Den har samma regler som servern för behörighet, `If-None-Match`, `seq`, felkoder och gränser, i minnet, och kan tvingas svara `500` eller kasta `URLError(.notConnectedToInternet)`.
- [ ] **Steg 2: Skriv tester som misslyckas** i `RelayHouseholdSyncTests.swift`:
  - `skapaOchBjudIn`: `create(myName: "Jesper")` och sedan `invite()` ger en URL som `HouseholdInviteLink(url:)` kan läsa. Läget har rollen `owner` och deltagaren "Jesper".
  - `gaMedSerAgarensAdresser`: medlemmen går med och ser ägarens delade adress med samma `SavedAddress.url`.
  - `serverFelBehallerHushallet`: med kopian sparad och servern på `500` blir läget `failed`, med samma adresser och bockar.
  - `forstaHamtningenSkickarBaraFel`: utan kopia och med servern på `500` skickas inget läge med tomt hushåll, bara `failed`.
  - `bara401GerFailedInteRemoved`
  - `removedOchEndedGerRemoved`
  - `notFoundGerFailed`
  - `sammaBockFranTvaTelefonerForstaVinner`: två synkar med var sin deltagare bockar samma `PlacedOut` utan nät och skickar sedan. Båda visar den förstas `by` och `at`, och den andras kö är tom.
  - `olasbarPostTarInteBortAdressen`: en känd adress vars post efter `full: true` inte går att dekryptera står kvar, och en okänd oläsbar post visas inte.
  - `bockUtanNatArPending`: `isPending` är `true` tills den har skickats, och den skickas vid nästa `fetchChanges`.
  - `angraTarBortBocken`
  - `nyEnhetSammaDeltagare`: en andra synk med samma `HouseholdCredentials` (som efter en återställning) blir samma deltagare och registrerar ett annat `deviceId`.
  - `signalGerHamtning`: ett värde i `signals` gör att ändringarna hämtas.
  - `namnSparasKrypterat`: `setMyName` ger ett namn som den falska servern bara ser som chiffertext, och som de andra ser i klartext.
- [ ] **Steg 3:** Kör `swift test --filter RelayHouseholdSync`. Förväntat: misslyckas.
- [ ] **Steg 4:** Implementera. Logiska namn som i CloudKit-specen (`AddressKey.fileName`, och `fileName + "-" + yyyy-MM-dd`). `expiresAt` är dagen efter hämtdatumet, 00:00 i Stockholm. Bara ändringar efter den senaste `seq` hämtas, och `full: true` ersätter kopian. Läget skickas bara när det har ändrats, som i CloudKit-synken.
- [ ] **Steg 5:** Kör `swift test`. Förväntat: alla gröna.
- [ ] **Steg 6:** Committa: `feat: Hushållets synk mot brevlådan`

## Uppgift 6: Flytten och valet av synk

**Files:**
- Create: `SophamtningKit/Household/HouseholdMigrator.swift`, `SophamtningKit/Household/RoutingHouseholdSync.swift`
- Modify: `SophamtningKit/Household/HouseholdLogic.swift`, `SophamtningKit/App/AppModel+Household.swift`
- Test: `HouseholdMigratorTests.swift`, `RoutingHouseholdSyncTests.swift`, `HouseholdLogicTests.swift`

**Interfaces:**
- Consumes: `RelayHouseholdSync`, `HouseholdMembership`, `FakeRelayServer` (uppgift 5).
- Produces:
  - `public protocol LegacyHousehold: HouseholdSync`:
    - `var legacyMyId: String? { get }`
    - `func legacySnapshot() async -> HouseholdState?`, där bockarnas `by` och `at` är de ursprungliga
    - `func migrationLink() async -> URL?`
    - `func writeMigrationLink(_ url: URL) async throws`
    - `func removeShare() async throws`
  - `public final class HouseholdMigrator` med `init(relay: RelayHouseholdSync, legacy: any LegacyHousehold, transport: any RelayTransport, store: LocalStore, now:)` och `func run() async`. Den kör ägarens eller medlemmens steg enligt specens punkt 4–7, och punkt 9 efter 90 dagar. Var flytten är sparas i `household-migration.json` (`createdAt`, `uploaded`, `linkWritten`).
  - `public final class RoutingHouseholdSync: HouseholdSync, HouseholdMembership` med `init(relay: RelayHouseholdSync, legacy: (any LegacyHousehold)?)`. Den använder brevlådan när `relay.hasHousehold`, annars CloudKit när CloudKit har ett hushåll, annars brevlådan. Den byter när flytten eller ett `join` är klart och skickar då det nya läget. `HouseholdMembership` på CloudKit kastar `HouseholdMembershipError.unsupported` (definieras i `HouseholdMembership.swift`), och arket visar då de gamla knapparna.
  - `HouseholdLogic.isKnown(_ participant: HouseholdParticipant, known: Set<String>) -> Bool`, som är sant om `id` eller något i `legacyIds` finns i `known`.

- [ ] **Steg 1: Skriv tester som misslyckas:**
  - `flyttenStartarBaraNarConfigSagerDet`: `migration: false` ger ingen flytt, och ingen förfrågan utom `/config`.
  - `agarenFlyttarAllt`: alla adresser och alla bockar som inte är förbrukade finns i brevlådan med `legacy` satt. Ägarens namn har `legacyIds`, och `writeMigrationLink` har fått en länk vars inbjudan gäller i 90 dagar.
  - `avbrutenFlyttFortsatterISammaHushall`: med fel efter `create` men före `writeMigrationLink` ger nästa `run()` samma `householdId` och skriver länken.
  - `medlemmenGarMedTyst`: en medlem med `migrationLink()` går med, sparar namnet med `legacyIds` och laddar inte upp några poster.
  - `ingenRadForFlyttadDeltagare`: efter flytten ger `noticeNewParticipants` ingen rad och ingen notis för någon vars `legacyIds` var känd. Inte heller "är inte längre med" för de gamla id:na.
  - `legacyByVisarRattNamn`: en bock med `legacy.by` = medlemmens CloudKit-id visar medlemmens nya namn och den ursprungliga tiden.
  - `efter90DagarTasDelningenBort`
  - `nyttHushallSkapasIBrevladan`: utan hushåll alls ger `create` ett hushåll i brevlådan, även när CloudKit finns.
- [ ] **Steg 2:** Kör `swift test --filter "HouseholdMigrator|RoutingHouseholdSync|HouseholdLogic"`. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera, och ta bort `HouseholdLogic.liveFetchInterval` och hämtningen var 15:e sekund där den används.
- [ ] **Steg 4:** Kör `swift test`. Förväntat: alla gröna.
- [ ] **Steg 5:** Committa: `feat: Hushåll flyttas från iCloud till brevlådan`

## Uppgift 7: Texter och AppModel för de nya valen

**Files:**
- Modify: `SophamtningKit/Household/HouseholdTexts.swift`, `SophamtningKit/App/AppModel+Household.swift`
- Test: `AppModelHouseholdTests.swift`, `HouseholdTextsTests` (i befintlig testfil för texter, om den finns, annars ny)

**Interfaces:**
- Consumes: `HouseholdMembership`, `RoutingHouseholdSync`.
- Produces på `AppModel`:
  - `inviteURL() async -> URL?`
  - `revokeInvites() async -> Bool`
  - `removeParticipant(_ id: String) async -> Bool`
  - `endHousehold() async -> Bool`
  - `receiveInvite(_ link: HouseholdInviteLink) async`, som följer samma regler som `HouseholdShareAcceptance` om att lämna först
  - `canManageMembers: Bool`, som är sant när brevlådan används och jag är ägare
- Produces i `HouseholdTexts`, ordagrant:
  - `inviteMessage = "Gå med i mitt hushåll i Sophämtning"`
  - `inviteMore = "Bjud in fler"`
  - `revokeInvites = "Gör inbjudningar ogiltiga"`
  - `revokeInvitesFooter = "Länkar du har skickat gäller i 7 dagar."`
  - `removeParticipant = "Ta bort ur hushållet"`
  - `inviteInvalid = "Inbjudan gäller inte längre. Be om en ny."`
  - `householdFull = "Hushållet är fullt."`
  - `intro` ändras till `"Dela adresser med dem du bor med. Ni ser samma schema, och när någon ställer ut kärlen syns det för alla. Hushållet krypteras på era telefoner, och bara ni kan läsa det."` Texten visas bara utan hushåll, och nya hushåll skapas alltid i brevlådan.
  - `removeConfirm(name:)`, med texten `"Ta bort {namn} ur hushållet? {namn} behåller adresserna som egna."` (min formulering, inom tonen i hushållsspecen)

- [ ] **Steg 1: Skriv tester som misslyckas:** `inbjudanGerLank`, `medlemKanInteHanteraMedlemmar`, `taBortDeltagareForsvinnerUrListan`, `ogiltigInbjudanVisarText`, `fulltHushallVisarText`, `inbjudanNarJagArMedFragarForst`, och att texterna ovan är exakt de angivna.
- [ ] **Steg 2:** Kör `swift test --filter AppModelHousehold`. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera.
- [ ] **Steg 4:** Kör `swift test`. Förväntat: alla gröna.
- [ ] **Steg 5:** Committa: `feat: Bjud in, ta bort och avsluta i hushållet i brevlådan`

## Uppgift 8: Appen: nyckelring, nät, push och länkar

**Files:**
- Create: `iOS/Sophamtning/Household/KeychainCredentialStore.swift`, `URLSessionRelayTransport.swift`, `HouseholdLinkAcceptance.swift`, `CloudKitHouseholdSync+Legacy.swift`
- Modify: `iOS/Sophamtning/SophamtningApp.swift`, `iOS/Sophamtning/Household/CloudKitHouseholdSync.swift`, `iOS/Sophamtning/Household/HouseholdRecords.swift` (posttypen `HushallFlytt`), `iOS/project.yml`, `iOS/Sophamtning/UITest/UITestAPI.swift`

**Interfaces:**
- Consumes: allt från uppgift 4–7.
- Produces:
  - `KeychainCredentialStore: HouseholdCredentialStore` med `kSecClassGenericPassword`, tjänsten `se.hardyson.sophamtning.hushall`, `kSecAttrSynchronizable: true` och `kSecAttrAccessibleAfterFirstUnlock`.
  - `URLSessionRelayTransport: RelayTransport` med bas-URL och User-Agent enligt Gemensamma krav. `signals` använder `URLSessionWebSocketTask` och kopplar upp igen efter 1, 2, 4 och sedan högst 30 sekunder.
  - `CloudKitHouseholdSync: LegacyHousehold`. `HushallFlytt` har postnamnet `flytt` och fälten `link` och `at`.

- [ ] **Steg 1:** `project.yml`: rättigheten `com.apple.developer.associated-domains` med `applinks:sopor.hardyson.se`, och `keychain-access-groups` med `$(AppIdentifierPrefix)se.hardyson.sophamtning`. Kör `cd iOS && xcodegen generate`.
- [ ] **Steg 2:** Koppla ihop i `SophamtningApp.swift`: `RoutingHouseholdSync(relay:legacy:)` ersätter `CloudKitHouseholdSync` som `HouseholdSync`. `HouseholdMigrator.run()` körs vid start och när appen blir aktiv. `startSignals()` körs när scenen blir aktiv, och `stopSignals()` när den går till bakgrunden.
- [ ] **Steg 3:** Push: push-tokenet från `didRegisterForRemoteNotificationsWithDeviceToken` skickas till `registerDevice`, med `environment` `sandbox` i Debug och `production` annars. En push med nyckeln `h` ger `fetchChanges()`, som en tyst push från CloudKit gör i dag.
- [ ] **Steg 4:** Länkar: `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` och `.onOpenURL` ger `HouseholdLinkAcceptance`. Den tolkar länken med `HouseholdInviteLink(url:)`. Är `isCurrent` sant hämtas bara ändringarna. Annars anropas `model.receiveInvite`, med samma fråga som i `HouseholdShareAcceptance`. En inbjudan som kommer innan appen har startat klart sparas, som i dag.
- [ ] **Steg 5:** UI-testerna: `UITestAPI` ger `InMemoryHouseholdSync` som förut. Startargumentet `-uitest-hushall-lank <url>` simulerar en öppnad länk.
- [ ] **Steg 6:** Bygg och kör `swift test`. Förväntat: bygget lyckas och testerna är gröna.
- [ ] **Steg 7:** Committa: `feat: Appen använder brevlådan för hushåll`

## Uppgift 9: Arket Hushåll

**Files:**
- Modify: `iOS/Sophamtning/Views/HouseholdSheet.swift`, `iOS/SophamtningUITests/HouseholdTests.swift`
- Delete when unused: inget. `CloudSharingView.swift` blir kvar för hushåll som inte har flyttats.

**Interfaces:**
- Consumes: `AppModel.inviteURL()`, `revokeInvites()`, `removeParticipant(_:)`, `canManageMembers` och texterna från uppgift 7.

- [ ] **Steg 1: Skriv UI-tester som misslyckas:** `testAgarenTarBortDeltagare` (svep, **Ta bort ur hushållet**, bekräfta, raden försvinner), `testGorInbjudningarOgiltiga` (knappen och texten under den syns) och `lankTillSammaHushallFragarInte` (med `-uitest-hushall-lank` till samma hushåll visas ingen dialog).
- [ ] **Steg 2:** Kör de tre med `-only-testing:SophamtningUITests/HouseholdTests/<namn>`. Förväntat: misslyckas.
- [ ] **Steg 3:** Implementera:
  - När `canManageMembers` är sant ersätter `ShareLink(item: url, message: Text(HouseholdTexts.inviteMessage))` och **Bjud in fler** knappen **Hantera medlemmar**.
  - **Väntar på svar** visas inte när brevlådan används.
  - Fältet **Ditt namn** fylls inte i från Apple-kontot när brevlådan används.
  - Komponenter, färger och typsnitt kommer från `SophamtningDesign`, med systemets mönster för svep och bekräftelse.
- [ ] **Steg 4:** Kör de tre UI-testerna och de befintliga i `HouseholdTests`. Förväntat: gröna.
- [ ] **Steg 5:** Ta skärmbilder av arket som ägare och som medlem, i ljust läge, mörkt läge och med största text. Jesper godkänner dem innan uppgift 10.
- [ ] **Steg 6:** Committa: `feat: Hantera medlemmar i hushållet utan iCloud`

## Uppgift 10: Dokument, enhetstest och PR för iOS

**Files:**
- Modify: `CLAUDE.md`, `docs/specs/2026-11-06-app-store.md`, `docs/specs/2026-11-06-enhetschecklista.md`, `docs/specs/2026-11-08-release.md`

- [ ] **Steg 1:**
  - `CLAUDE.md`: meningen om att det inte finns någon egen backend ersätts med att `Server/` är brevlådan för hushåll. Kommandona `cd Server && npm test` och `npx wrangler deploy` läggs till.
  - App Store-specen: stycket om hushåll säger att innehållet är krypterat hos Cloudflare, och vad servern ser. Där står också Jespers beslut om push-token och deltagar-id.
  - Releasespecen: en punkt om att `MIGRATION` slås på först efter att Jesper har sett nya hushåll fungera.
- [ ] **Steg 2:** Enhetschecklistan: lägg till fallen från specens Test, med nummer efter de befintliga H-punkterna.
  - Flytt med två iPhones.
  - En medlem med gammal version.
  - Länk utan appen installerad.
  - Ny iPhone som återställs.
  - Flygplansläge.
  - Ta bort en deltagare.
- [ ] **Steg 3:** Kör hela UI-sviten och `swift test`. Förväntat: gröna. Stäng simulatorerna efteråt.
- [ ] **Steg 4:** Installera på Jespers iPhone och gå igenom de nya punkterna i enhetschecklistan som går med en telefon. Resten görs med två telefoner.
- [ ] **Steg 5:** Committa `docs: Hushåll i brevlådan i checklistor och App Store-specen`, och gör PR:en `feat: Hushåll som fungerar mellan iOS och Android`.

## Uppgift 11: Sopor-repot: länkarna

Görs i `jesperhardyson/sopor`, på en egen gren och i en egen PR, innan uppgift 8 provas på enhet.

- [ ] **Steg 1:** `public/.well-known/apple-app-site-association` (utan filändelse, `Content-Type: application/json` via `vercel.json`) med `applinks.details[].appIDs: ["<TEAMID>.se.hardyson.sophamtning"]` och `components: [{"/": "/hushall"}]`.
- [ ] **Steg 2:** `public/.well-known/assetlinks.json` med relationen `delegate_permission/common.handle_all_urls`, paketnamnet `se.hardyson.sophamtning` och SHA-256-fingeravtrycket för Play App Signing. Jesper hämtar fingeravtrycket i Play Console, under appens integritet. Uppladdningsnyckelns fingeravtryck är fel värde.
- [ ] **Steg 3:** Sidan `/hushall`, i webbens stil. Texten säger att det är en inbjudan till ett hushåll i Sophämtning och länkar till App Store och Google Play (den senare när appen finns där), och att länken ska öppnas igen när appen är installerad. Sidan läser aldrig `location.hash`. Rubriker och CSP som de andra sidorna.
- [ ] **Steg 4:** Kontrollera efter driftsättningen att `curl -sI https://sopor.hardyson.se/.well-known/apple-app-site-association` ger `200` och `application/json`.
- [ ] **Steg 5:** Committa `feat: Länkar till hushåll öppnar appen` och gör PR:en där.
