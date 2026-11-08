# Bidra till Sophämtning

Tack för att du vill hjälpa till!

## Var hör ditt ärende hemma?

| Du vill … | Gör så här |
|---|---|
| tipsa om en kommun | Öppna ett [ärende i sopor](https://github.com/jesperhardyson/sopor/issues/new?template=ny-kommun.md) |
| rapportera fel i schemat | Öppna ett [ärende i sopor](https://github.com/jesperhardyson/sopor/issues/new?template=fel-i-schemat.md) |
| rapportera fel i appen | Öppna ett [ärende här](https://github.com/jesperhardyson/Sophamtning/issues/new?template=fel-i-appen.md) |
| rapportera en säkerhetsbrist | Följ [`SECURITY.md`](SECURITY.md) |

**Skriv inte din hemadress i ett publikt ärende.** Ange en annan adress på samma gata eller bara kommunen, om det räcker för att visa felet. Det går också bra att mejla support@hardyson.se.

## Så arbetar vi

Större ändringar går i den här ordningen:

1. **Spec** i `docs/specs/`, som beskriver vad som ska byggas och varför.
2. **Design** i `docs/design/sophamtning-design.pen`, som är facit för utseendet.
3. **Plan** i `docs/plans/`, som delar upp arbetet i testbara uppgifter.
4. **Kod**, med tester först.

Mindre rättningar behöver bara en pull request.

## Pull requests

1. Forka repot och skapa en gren: `fix/kort-beskrivning` eller `feature/kort-beskrivning`.
2. Skriv tester och gör ändringen.
3. Öppna en pull request med titeln `fix: Beskrivning` eller `feat: Beskrivning` och fyll i mallen. Titeln följer [Conventional Commits](https://www.conventionalcommits.org/sv/v1.0.0/), eftersom den blir commit-meddelandet på `main` och styr versionen. Ändringar i bara dokumentation får `docs:`. Releaser görs inte för hand: Release Please håller en release-PR med nästa version, och när den mergas laddas appen upp till TestFlight efter godkännande.

`main` är skyddad. Ändringar går via pull request, och förvaltaren granskar dem.

## Regler

- **Bara Sopor API v1.** Appen talar med det publika API:t och aldrig med kommunernas tjänster direkt.
- **Högst en hämtning i timmen per adress.** Tjänsten drivs utan kostnad av en privatperson.
- **Gissa aldrig** vilken adress som hör till vilket område. En gissning som blir fel får folk att missa sin tömning.
- **Tekniska fel får aldrig se ut som att en adress eller kommun saknas.**
- **Opt-in.** Notiser och Live Activities är avstängda tills användaren slår på dem.
- **Ingen spårning.** Appen samlar inte in analysdata.
- **Svenska** i appen, kommentarer och commit-meddelanden.

## Hemligheter

Certifikat, `.p8`- och `.p12`-nycklar, provisioneringsprofiler och andra hemligheter får aldrig committas. Repot är publikt, så en hemlighet som har pushats ska ses som läckt och bytas ut, även om den tas bort direkt.

Genom att bidra godkänner du att ditt bidrag licensieras under [MIT](LICENSE).
