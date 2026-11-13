# Påminnelserna i Inställningar, uppdelade efter vad de styr

Status: godkänd av Jesper 2026-11-13, efter ett prov i simulatorn.

## Varför

Avsnittet Påminnelser i Inställningar hade fyra rader i samma kort: Notiser, Huvudadress, Live Activity och Visas från. Det syntes inte vad som hörde ihop, eller vad varje rad gällde. På sidan Notiser gick det inte att slå av båda tiderna, och det såg ut som ett fel, eftersom notiser slås på och av per adress och det inte syntes där.

## Mål

- Varje inställning står under en rubrik som säger vad den styr, med en rad under kortet som säger vad den gäller.
- Allt om notiser går att göra på sidan Notiser, även att stänga av dem helt.

## Inte med

- Ingen ändring av hur notiser, Live Activity eller huvudadressen fungerar. Bara var de visas och vad som står.
- Notiserna slås fortfarande på per adress. Ingen ny huvudbrytare.

## Inställningar

Tre avsnitt i stället för Påminnelser, i den här ordningen, före Delning:

| Avsnitt | Kortet | Texten under kortet |
|---|---|---|
| **Notiser** | Raden **Tid** med tiderna, till exempel "15:00 och 06:00", som öppnar sidan Notiser | Vilka adresser som får notiser: "Gäller Hemma. Slå på eller av i varje adress.", "Gäller Hemma och Jobbet. …", eller "Ingen adress har notiser på. Slå på Påminn mig i adressen." |
| **Live Activity** | Reglaget Live Activity och, när det är på, **Visas från** | "Visas för huvudadressen, Hemma." Utan huvudadress står ingen text. |
| **Huvudadress** | Huvudadressens namn, som öppnar valet av huvudadress | "Används av Live Activity, widgetar och Siri." Avsnittet visas bara när det finns en huvudadress. |

- Påminnelsen som har passerat står under Notiser. Meddelandena om Live Activity står under Live Activity.
- En adress räknas som att den får notiser när Påminn mig är på och iOS tillåter notiser, samma regel som i adressvyn.

## Sidan Notiser

- Överst avsnittet **Adresser**, med ett reglage per sparad adress i samma ordning som på hemskärmen. Reglaget är samma som Påminn mig i adressvyn och frågar om tillåtelse på samma sätt. Under: "Samma som Påminn mig i varje adress. Stäng av alla för att inte få några notiser."
- Utan sparade adresser visas inte avsnittet.
- Kvällen före och Samma morgon står kvar under. Texten under Samma morgon slutar med "Minst en påminnelse är på. Notiser slår du av under Adresser." i stället för "… per adress."

## Test

- **Paketet:** texterna under Notiser för noll, en, två och tre adresser, texten under Live Activity och Huvudadress, och den ändrade texten under Samma morgon.
- **UI:** Granskningen hittar raden Tid i stället för Notiser. Granskningen körs före release, som vanligt.
