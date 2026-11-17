# Meddelanden från källan i appen

Status: godkänd av Jesper 2026-11-17. Issue #78.

## Varför

Sopor API:t har fått fältet `messages`: tillfälliga besked från källan, till exempel att Avesta Vatten och Avfall lägger om hämtrutterna under hösten 2026 och att schemat kan bli fel. Sajten visar dem redan. Appen ska också visa dem och knuffa användaren en gång per nytt meddelande.

Serverns del är specad i `jesperhardyson/sopor`, `docs/specs/2026-11-17-kallmeddelanden.md`, och är ute i produktion. `GET /api/v1/kallor` ger i dag Avestas `nya-rutter-2026`.

## Mål

- Startsidan visar ett kort per meddelande som gäller för någon sparad adress.
- Den som inte har appen öppen när ett nytt meddelande kommer får en lokal notis, om notiser redan är tillåtna.
- Varje meddelande ger antingen kortet utan notis eller en notis, aldrig två notiser.

## Inte med

- Pushnotiser från servern. Notisen skickas av appen själv när bakgrundsuppdateringen hittar ett nytt meddelande.
- Meddelanden i adressvyn, widgeten, Live Activity eller Siri.
- Ny design i Pencil. Kortet byggs av `MessageCard` i `SophamtningDesign`, och designfilen uppdateras efteråt.
- `/omraden` och `/kallor`. Appen läser bara meddelandena i adressvaret.

## Får inte hända

- Appen frågar om tillstånd för notiser för meddelandenas skull.
- Samma meddelande ger två notiser, oavsett hur många sparade adresser som hör till källan.
- En fil med sedda meddelanden som inte går att läsa gör att alla meddelanden notifieras på nytt. Då skickas ingen notis alls.
- Ett utgånget meddelande visas från ett sparat svar.
- Ett svar utan `messages`, eller med ett trasigt fält, fäller schemat.

## API:t

`AddressResponse` får `messages: [SourceMessage]`:

```swift
public struct SourceMessage: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let text: String
    public let url: URL?
    public let validFrom: DayDate
    public let validTo: DayDate
}
```

- Saknas fältet, är det `null` eller trasigt blir det `[]`. Ett trasigt meddelande tas bort och fäller inte de andra (`Lenient`, som för `sources`).
- Sparade svar från äldre versioner saknar fältet och avkodas med `[]`. Nästa hämtning ger meddelandena.
- Källans id är `address.source`.

## Vilka meddelanden som gäller

Ett meddelande gäller när `validFrom <= i dag <= validTo`, med i dag i `Europe/Stockholm`. Det räknas om i appen, eftersom ett sparat svar kan vara äldre än `validTo`.

Meddelandena samlas från alla sparade adressers sparade svar, och nyckeln är källans id och meddelandets id. Samma meddelande hos flera adresser blir ett. Ordningen är `validFrom` och sedan `id`, som i API:t.

## Startsidan

- Ett `MessageCard` per meddelande som gäller och inte är stängt, överst under felrutorna och före förslaget om påminnelser. Stil `neutral` och ikonen `megaphone`.
- Rubrik och text som i API:t. Finns `url` visas en länk under texten, "Läs mer hos <källans namn>" med källans namn från den sparade källistan, eller "Läs mer" när namnet inte finns. Det är samma ordval som på sajten.
- Kortet har en stängknapp ("Stäng meddelandet" för VoiceOver). Ett stängt meddelande sparas och visas inte igen på den här telefonen.
- `MessageCard` får en valfri stängknapp och en valfri länk. Befintliga användningar ändras inte.

## Inställningar

- Under avsnittet Notiser, efter raden Tid: reglaget **Meddelanden från källan**, på från början.
- Reglaget står i ett eget kort under raden Tid, i samma stil som adressernas reglage på sidan Notiser, så att rubriken får plats på en rad. Texten under kortet: "Notis när källan har ett viktigt besked, till exempel att hämtrutterna läggs om. Skilt från påminnelserna."
- När iOS inte tillåter notiser är reglaget avstängt och texten slutar med "Notiser är avstängda för appen i iOS." Reglaget frågar aldrig om tillstånd.
- Valet sparas i `ReminderSettings` som `sourceMessagesOn`. Inställningar sparade före fältet läses som `true`.

## När ett meddelande räknas som sett

Varje gång adressernas schema hämtas (`refreshAll`) jämförs meddelandena som gäller med de som redan är sedda.

- `refreshAll` får parametern `context: RefreshContext` med `.foreground` och `.background`. `BackgroundRefreshRun` skickar `.background`, allt annat `.foreground`. Den är skild från `startingActivities`.
- Ett nytt meddelande i förgrunden: kortet visas, och det räknas som sett utan notis.
- Ett nytt meddelande i bakgrunden: en notis skickas med `deliverNow`, om `sourceMessagesOn` är på och iOS tillåter notiser. Det räknas som sett i alla fall, så att det inte blir en notis senare.
  - Notisens rubrik är källans namn, eller "Sophämtning" när namnet inte finns. Texten är meddelandets rubrik.
  - Identifieraren är `kalla.<källa>.<id>`. `NotificationDiff.isOwn` känner inte igen den, så planeringen tar aldrig bort notisen.
- Det gäller även meddelanden som redan var ute när appuppdateringen släpptes. Den som öppnar appen efter uppdateringen ser kortet. Den som får en bakgrundsuppdatering först får notisen.
- En adress som läggs till hämtas i förgrunden, så dess meddelanden visas som kort utan notis.

## Lagring

Ny fil `source-messages.json` i App Group-mappen:

```json
{ "avesta": { "seen": ["nya-rutter-2026"], "dismissed": [] } }
```

- Nyckeln är källans id, så att samma `id` hos två källor inte krockar.
- Sett och stängt är skilda. Ett sett meddelande visas som kort tills det stängs.
- Inget tas bort ur filen. Ett `id` återanvänds aldrig, och filen blir några rader stor.
- Går filen inte att läsa (skadad eller skyddad) skickas inga notiser för meddelanden och inget skrivs över. Korten visas som om inget var stängt. Saknas filen är allt osett.
- En ominstallation nollställer filen. Kortet kommer då tillbaka, och ingen notis skickas om appen är öppen.

## CLAUDE.md

Regeln "Notiser och Live Activities är avstängda från början. Inget schemaläggs utan användarens val." får tillägget: "Undantag: Meddelanden från källan är på från början, men en sådan notis skickas bara när iOS redan tillåter notiser, och appen frågar aldrig om tillstånd för den."

## Test

- **Avkodning:** adressvar med `messages`, utan fältet, med `null`, med ett trasigt meddelande bland hela, och ett sparat `CachedSchedule` från före fältet.
- **Vilka som gäller:** före `validFrom`, sista dagen `validTo`, efter `validTo`, och dagsbyte i Stockholm när telefonen står i en annan tidszon.
- **Ihopslagning:** två adresser hos samma källa ger ett kort. Samma `id` hos två källor ger två.
- **Sett:** nytt i förgrunden ger ingen notis och räknas som sett. Nytt i bakgrunden ger en notis. Samma meddelande nästa körning ger ingen ny. Reglaget av ger ingen notis. iOS nekat ger ingen notis. Oläslig fil ger ingen notis och skriver inte över.
- **Stängt:** ett stängt kort visas inte, och de andra står kvar.
- **Inställningar:** `sourceMessagesOn` saknas i sparade inställningar och läses som `true`. Texten under reglaget med och utan tillstånd.
- **UI-test:** inget nytt. `UITestAPI` får ett meddelande för en adress, så att kortet syns i granskningen av tillgänglighet och största text.
