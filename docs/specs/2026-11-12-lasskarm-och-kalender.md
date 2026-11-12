# Låsskärmen, Ställ ut i widgeten, Kontrollcenter och Kalender

Status: godkänd av Jesper 2026-11-12.

## Mål

Den som har sparat en adress ser nästa tömning utan att öppna appen, och kan markera kärlen som utställda med ett tryck där de redan är: i widgeten, i Kontrollcenter och på Action-knappen. Schemat kan också läggas in i Kalender.

- Allt räknas från det sparade schemat, utan nätanrop, med samma regler som hemskärmen och den mellanstora widgeten (`WidgetContent`). "I dag" räknas i `Europe/Stockholm`.
- Ställ ut kärlen gör överallt samma sak som Klart i Live Activityn, Utställt i notisen och Siri (`MarkPlacedOutIntent.markPlacedOut`): bocken sparas, tömningens påminnelser och Live Activity tas bort, och i ett hushåll skickas bocken.
- Widgetarna och kontrollen gäller huvudadressen, som de befintliga widgetarna.

## Inte med

- Apple Watch. Låsskärmens widgetar visas inte på klockan utan en egen klocka-app.
- Val av adress i widget och kontroll.
- Ångra i widget och kontroll. Ångra finns i appen.

## 1. Widgetar på låsskärmen

Stryker "Widgets på låsskärmen" under Inte med i `docs/specs/2026-11-06-ios-app.md`. Tre storlekar, i systemets färger på låsskärmen (ingen egen bakgrund):

| Storlek | Nästa tömning | Utställt |
|---|---|---|
| Rad ovanför klockan (`accessoryInline`) | "Ons 25 nov: Mat, Papper", eller "I morgon: Mat, Papper" och "I dag: …" | "Utställt: Mat, Papper" |
| Rektangel (`accessoryRectangular`) | Rubrik "Om 13 dagar" (eller "I morgon", "I dag", med "ca" för beräknat), datumet "Ons 25 nov" och kärlen med korta namn "Mat, Papper" | Tredje raden blir "Utställt" med en bock |
| Cirkel (`accessoryCircular`) | Ikonen `trash` och dagar kvar: "13", "1" i morgon, "0" i dag, under siffran "dgr" | En bock i stället för siffran |

- Kärlen är bara de som töms det datum som är nästa tömning, som i den mellanstora widgeten, med källans korta namn. Får de inte plats kapas raden med "…".
- Utan huvudadress, utan schema eller med oläsliga filer: rektangeln och raden säger "Sophämtning" och "Öppna appen", och cirkeln visar bara ikonen. Ett tekniskt fel låter aldrig som att adressen saknas.
- VoiceOver läser samma mening som den lilla widgeten.
- Hemskärmens storlekar fungerar redan i StandBy och ändras inte.

## 2. Ställ ut kärlen i den mellanstora widgeten

- När nästa tömning är i dag eller i morgon och inte är utställd står knappen **Ställ ut kärlen** i den mellanstora widgeten, i stället för den sista raden när det behövs plats. Samma gräns som knappen på huvudkortet, men för huvudadressen även när den inte är delad.
- Ett tryck kör `MarkPlacedOutIntent` för tömningen utan att öppna appen. Widgeten laddas om och visar **Utställt** som i dag.
- Den lilla widgeten får ingen knapp, eftersom den saknar plats.

## 3. Kontroll i Kontrollcenter och på Action-knappen

- En `ControlWidgetButton`, **Ställ ut kärlen**, med symbolen `checkmark.circle`. Den går att lägga i Kontrollcenter, på låsskärmen och på Action-knappen.
- Ett tryck kör samma regel som Siris Ställ ut kärlen för huvudadressen (`SiriAnswers.placeOut`): i dag eller i morgon markeras tömningen. Annars händer ingenting, och kontrollen visar kort nästa tömnings datum, till exempel "Ons 25 nov".
- Kontrollens värde visar läget: "I morgon", "I dag", "Utställt" eller nästa datum.

## 4. Lägg till i Kalender

- Adressvyn får ett eget avsnitt **Kalender**, före kortet om källan, med raden **Lägg till i Kalender** och texten "Tömningarna läggs in som en egen kalender, som uppdateras av sig själv." Raden öppnar adressens `links.ics` med schemat `webcal://`, så att iOS frågar om prenumeration i Kalender. Kalendern uppdateras sedan av iOS, utan appen.
- Avsnittet visas bara när svaret har en `links.ics`. Live-källor utan schema har ingen.
- Prenumerationen är användarens egen och syns inte i appen. Appen läser aldrig Kalender och behöver ingen behörighet.

## Arkitektur

- **`SophamtningKit`:** `LockScreenContent` räknar texterna för de tre låsskärmsstorlekarna från `WidgetContent`. `WidgetContent` får avgörandet om knappen Ställ ut kärlen visas. `CalendarLink` gör `webcal://`-adressen av `links.ics`. Allt testas med `swift test`.
- **Widgetmålet:** de nya storlekarna i `NextPickupWidget`, knappen med `Button(intent:)`, och kontrollen i `SophamtningWidgetBundle`. `PlaceOutIntent` och det den använder ingår i både appens och widgetarnas mål, som `MarkPlacedOutIntent` redan gör.
- Inga nya rättigheter.

## Test

- **Paketet:** varje rad i tabellen för låsskärmen, med beräknat datum, i dag, i morgon och utställt. När knappen och kontrollen markerar och när de inte gör det. `webcal://` av en `https://`-länk och en saknad länk.
- **Enhet:** fallen läggs i `docs/specs/2026-11-06-enhetschecklista.md`: lägg till de tre låsskärmswidgetarna, tryck Ställ ut kärlen i widgeten med låst telefon, lägg kontrollen i Kontrollcenter och på Action-knappen, och prenumerera på kalendern.
