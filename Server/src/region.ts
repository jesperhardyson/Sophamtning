/**
 * Låser objekten till EU. Den lokala miljön stöder inte det, så testerna stänger av det med `LOCAL_ONLY_NO_JURISDICTION`.
 * Variabeln finns inte i `wrangler.jsonc`, och utan den är låset alltid på.
 */
export function inEU<T extends Rpc.DurableObjectBranded | undefined>(namespace: DurableObjectNamespace<T>, env: object): DurableObjectNamespace<T> {
  return "LOCAL_ONLY_NO_JURISDICTION" in env ? namespace : namespace.jurisdiction("eu");
}
