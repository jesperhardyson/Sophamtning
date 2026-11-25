import { generateKeyPairSync } from "node:crypto";
import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Nycklarna finns bara så länge testerna körs. De publika låter testerna kontrollera signaturerna.
const apns = generateKeyPairSync("ec", { namedCurve: "P-256" });
const fcm = generateKeyPairSync("rsa", { modulusLength: 2048 });
const pem = (key: typeof apns.privateKey) => key.export({ type: "pkcs8", format: "pem" }).toString();

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          LOCAL_ONLY_NO_JURISDICTION: "1",
          APNS_KEY: pem(apns.privateKey),
          APNS_KEY_ID: "ABC123DEFG",
          APNS_TEAM_ID: "TEAM123456",
          FCM_SERVICE_ACCOUNT: JSON.stringify({ project_id: "prov", client_email: "push@prov.iam.gserviceaccount.com", private_key: pem(fcm.privateKey) }),
          TEST_APNS_PUBLIC: JSON.stringify(apns.publicKey.export({ format: "jwk" })),
          TEST_FCM_PUBLIC: JSON.stringify(fcm.publicKey.export({ format: "jwk" })),
        },
      },
    }),
  ],
});
