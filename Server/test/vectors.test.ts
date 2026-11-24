import { describe, expect, it } from "vitest";
import { b64url, fromB64url } from "../src/encoding";
import vectors from "./vectors.json";

const encoder = new TextEncoder();

async function keys(householdKey: string) {
  const master = await crypto.subtle.importKey("raw", fromB64url(householdKey), "HKDF", false, ["deriveBits"]);
  const derive = async (info: string) =>
    new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encoder.encode(info) }, master, 256));
  return { content: await derive("sophamtning-hushall-innehall-v1"), name: await derive("sophamtning-hushall-postnamn-v1") };
}

async function hmac(key: Uint8Array, text: string) {
  const imported = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64url(new Uint8Array(await crypto.subtle.sign("HMAC", imported, encoder.encode(text))));
}

async function seal(key: Uint8Array, nonce: string, aad: string, plaintext: string) {
  const imported = await crypto.subtle.importKey("raw", key, "AES-GCM", false, ["encrypt"]);
  const iv = fromB64url(nonce);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: encoder.encode(aad) }, imported, encoder.encode(plaintext)));
  return b64url(new Uint8Array([...iv, ...sealed]));
}

/** Formatet som apparna följer. Samma fil läses av testerna på iOS och Android. */
describe("Testvektorer", () => {
  for (const vector of vectors.records) {
    it(`post: ${vector.title}`, async () => {
      const { content, name } = await keys(vectors.householdKey);
      expect(await hmac(name, vector.logical)).toBe(vector.name);
      const aad = `${vectors.householdId}.${vector.name}.${vector.kind}`;
      expect(await seal(content, vector.nonce, aad, vector.plaintext)).toBe(vector.data);
    });

    it(`logiskt namn: ${vector.title}`, async () => {
      const plain = JSON.parse(vector.plaintext);
      const { source, id } = plain.address?.key ?? plain;
      const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(`${source}\0${id}`)));
      const fileName = [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
      expect(vector.logical).toBe(plain.date ? `${fileName}-${plain.date}` : fileName);
    });
  }

  for (const vector of vectors.names) {
    it(`namn: ${vector.title}`, async () => {
      const { content } = await keys(vectors.householdKey);
      const aad = `${vectors.householdId}.${vector.participantId}.name`;
      expect(await seal(content, vector.nonce, aad, vector.plaintext)).toBe(vector.data);
    });
  }
});
