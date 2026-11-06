# Sophämtning

Native-appar för iOS och Android som visar när sopkärlen töms och påminner dig om att ställa ut dem. Inget konto behövs, och dina adresser sparas bara i telefonen.

Sophämtning är **inofficiell** och inte kopplad till någon kommun eller något avfallsbolag. Vid avvikelser gäller alltid kommunens information.

## Läge

Projektet är i planeringsfasen. iOS byggs först och Android senare. Ingen app är publicerad än.

## Så hänger det ihop

Apparna bygger på det öppna [Sopor API v1](https://sopor.hardyson.se/api/v1/docs) från projektet [sopor](https://github.com/jesperhardyson/sopor). API:t är appens enda kontrakt mot Sopor, och här finns ingen egen backend.

| Katalog | Innehåll |
|---|---|
| `iOS/` | iOS-appen i Swift och SwiftUI |
| `Android/` | Android-appen, senare |
| `docs/specs/` | Specifikationer |
| `docs/plans/` | Implementationsplaner |
| `docs/design/` | Design i Pencil |

## Bidra

Läs [`CONTRIBUTING.md`](CONTRIBUTING.md). Saknas din kommun, eller är schemat fel, görs det i [sopor](https://github.com/jesperhardyson/sopor), eftersom datan finns där. Säkerhetsbrister rapporteras enligt [`SECURITY.md`](SECURITY.md).

## Licens

Koden är [MIT-licensierad](LICENSE). Tredjepartsmaterial listas i [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

Licensen ger ingen rätt att använda namnet Sophämtning eller logotypen på ett sätt som ger sken av att en annan app är den här appen eller är officiell.
