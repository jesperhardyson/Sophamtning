import { expect, it } from "vitest";
import { inEU } from "../src/region";
import wrangler from "../wrangler.jsonc?raw";

const namespace = { jurisdiction: (name: string) => `i ${name}` } as unknown as DurableObjectNamespace;

it("hushallenLiggerIEU", () => {
  expect(inEU(namespace, {})).toBe("i eu");
  expect(inEU(namespace, { LOCAL_ONLY_NO_JURISDICTION: "1" })).toBe(namespace);
});

it("driftenStangerAldrigAvLaset", () => {
  expect(wrangler).not.toContain("LOCAL_ONLY_NO_JURISDICTION");
});
