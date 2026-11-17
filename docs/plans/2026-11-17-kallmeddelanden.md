# Plan: Meddelanden från källan i appen

Spec: `docs/specs/2026-11-17-kallmeddelanden.md`. Issue #78. Varje steg skrivs med testet först, och `swift test` körs efter varje steg.

## 1. Avkodning (`APIModels.swift`)

- `SourceMessage` med `id`, `title`, `text`, `url`, `validFrom`, `validTo`. En `url` som inte går att tolka blir `nil`.
- `AddressResponse.messages`, avkodad med `Lenient`, och `[]` när fältet saknas, är `null` eller trasigt. Init-parametern har standardvärdet `[]`.
- Test i `SourceMessagesTests`: med, utan, `null`, ett trasigt bland hela, och ett sparat `CachedSchedule` utan fältet.

## 2. Vilka som gäller (`Messages/SourceMessages.swift`)

- `ActiveSourceMessage` (källa och meddelande, `id` = `källa/id`).
- `SourceMessages.active(in:today:)` tar par av källa och svar, filtrerar på datum, slår ihop dubbletter och sorterar på `validFrom` och `id`.
- Test: före `validFrom`, sista dagen, efter `validTo`, två adresser hos samma källa, samma `id` hos två källor, ordningen.

## 3. Minnet (`SourceMessageMemory`) och `LocalStore`

- `SourceMessageMemory` kodas som `{ "<källa>": { "seen": [], "dismissed": [] } }`, med `isSeen`, `isDismissed`, `markSeen` och `dismiss`.
- `LocalStore.sourceMessageMemoryState()` och `setSourceMessageMemory(_:)` för `source-messages.json`.
- `SourceMessages.unseen(_:memory:)` ger de som inte är sedda.
- Test: kodningens form, fil som saknas, skadad fil.

## 4. Inställningen

- `ReminderSettings.sourceMessagesOn`, `true` från början och när fältet saknas.
- `ReminderSettingsTexts.sourceMessagesFooter(authorized:)`.
- Test: gamla inställningar läses som på, och texterna.

## 5. AppModel

- `RefreshContext` med `.foreground` och `.background`. `refreshAll(manual:startingActivities:context:)` med `.foreground` som standard. `BackgroundRefreshRun` skickar `.background`.
- Efter varje uppdatering: de som gäller och inte är sedda markeras som sedda. I bakgrunden skickas först `deliverNow` för var och en, om `sourceMessagesOn` är på och iOS tillåter notiser. Är minnet oläsligt händer ingenting.
- `visibleSourceMessages` för startsidan, utan stängda. `dismissSourceMessage(_:)` och `setSourceMessagesOn(_:)`.
- `sourceName(for:)` från den sparade källistan.
- Test (`AppModelSourceMessagesTests`): förgrund utan notis, bakgrund med notis, ingen notis andra gången, reglaget av, iOS nekat, oläsligt minne, stängt kort, två adresser ger en notis.

## 6. Utseendet

- `MessageCard` får valfri stängknapp och valfri länk.
- `HomeView` visar korten under felrutorna. `SettingsView` får reglaget under Notiser.
- `UITestAPI` får ett meddelande för Avesta, så att kortet syns i granskningen.

## 7. Verifiering

- `swift test`, bygget, och UI-testerna som rör startsidan och inställningarna.
- Skärmdumpar från simulatorn av startsidan och inställningarna.
