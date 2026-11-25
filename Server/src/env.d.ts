// Hemligheterna läggs in med `wrangler secret put` och finns inte i wrangler.jsonc. Saknas de skickas ingen push.
interface Env {
  /** Innehållet i `.p8`-filen från Apple Developer. */
  APNS_KEY?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  /** Tjänstekontots JSON från Firebase. */
  FCM_SERVICE_ACCOUNT?: string;
}
