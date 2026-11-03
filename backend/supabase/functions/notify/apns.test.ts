// Unit tests for the push helpers: `deno test notify/`. The key is made
// here, so nothing touches Apple.

import { assert, assertEquals, assertRejects, assertThrows } from "jsr:@std/assert@1";
import {
  apnsConfig,
  apnsHost,
  classify,
  deliverAll,
  describe,
  MESSAGE_CATEGORY,
  MESSAGE_THREAD,
  messagePayload,
  pkcs8FromP8,
  providerToken,
  send,
  testPayload,
  TokenCache,
} from "./apns.ts";

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const fromB64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

async function makeKey() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const body = b64(der).replace(/(.{64})/g, "$1\n");
  const pem = `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`;
  return { pair, der, pem };
}

Deno.test("apnsConfig needs all three secrets", () => {
  const env = (vars: Record<string, string>) => (name: string) => vars[name];
  assertEquals(apnsConfig(env({})), null);
  assertEquals(apnsConfig(env({ APNS_KEY_ID: "ABC", APNS_TEAM_ID: "TEAM" })), null);
  assertEquals(apnsConfig(env({ APNS_KEY_ID: " ABC ", APNS_TEAM_ID: "TEAM", APNS_PRIVATE_KEY: "k" })), {
    keyId: "ABC",
    teamId: "TEAM",
    privateKey: "k",
  });
});

Deno.test("the .p8 text reads however it was pasted", async () => {
  const { der, pem } = await makeKey();
  assertEquals(pkcs8FromP8(pem), der);
  assertEquals(pkcs8FromP8(pem.replace(/\n/g, "\\n")), der, "line breaks written \\n");
  assertEquals(pkcs8FromP8(btoa(pem)), der, "the whole file in base64");
  assertEquals(pkcs8FromP8(b64(der)), der, "the bare body");
  assertThrows(() => pkcs8FromP8("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----"), Error, "holds no key");
});

Deno.test("providerToken is an ES256 JWT Apple can check", async () => {
  const { pair, pem } = await makeKey();
  const key = await crypto.subtle.importKey("pkcs8", pkcs8FromP8(pem), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const jwt = await providerToken({ keyId: "KEY1234567", teamId: "TEAM123456", privateKey: pem }, key, 1_800_000_000.7);
  const [head, claims, sig] = jwt.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(fromB64url(head))), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(JSON.parse(new TextDecoder().decode(fromB64url(claims))), { iss: "TEAM123456", iat: 1_800_000_000 });
  assertEquals(fromB64url(sig).length, 64, "raw r‖s");
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, fromB64url(sig),
    new TextEncoder().encode(`${head}.${claims}`));
  assert(ok, "the signature checks out");
});

Deno.test("TokenCache keeps a token for 50 minutes", async () => {
  const { pem } = await makeKey();
  const config = { keyId: "K", teamId: "T", privateKey: pem };
  const cache = new TokenCache();
  const a = await cache.get(config, 1000);
  assertEquals(await cache.get(config, 1000 + 49 * 60), a, "the same within 50 minutes");
  const b = await cache.get(config, 1000 + 51 * 60);
  assert(b !== a, "a new one after");
  assertEquals(await cache.get(config, 1000 + 52 * 60), b, "kept again");
  cache.forget();
  assert((await cache.get(config, 1000 + 52 * 60)) !== b, "and made anew after Apple calls it expired");
  assert((await cache.get({ ...config, keyId: "K2" }, 1000 + 51 * 60)).length > 0, "a new key id, a new token");
  await assertRejects(() => new TokenCache().get({ ...config, privateKey: "not a key" }, 0));
});

Deno.test("messagePayload: who, what, the badge, Reply", () => {
  const p = messagePayload({ id: "m1", sender_name: "Mia", body: "Can I have a snack?", device_name: "Kitchen", displays: 1, unread: 3 });
  assertEquals(p, {
    aps: { alert: { title: "Mia", body: "Can I have a snack?" }, sound: "default", "thread-id": MESSAGE_THREAD, category: MESSAGE_CATEGORY, badge: 3 },
    message_id: "m1",
  });
  const two = messagePayload({ id: "m2", sender_name: "Mia", body: "hi", device_name: "Den", displays: 2, unread: 0 });
  assertEquals((two.aps as { alert: { subtitle?: string } }).alert.subtitle, "Den", "two displays: which one");
  const self = messagePayload({ id: "m3", sender_name: "Den", body: "hi", device_name: "Den", displays: 2 });
  assertEquals((self.aps as { alert: { subtitle?: string } }).alert.subtitle, undefined, "the display's own name once");
  assertEquals((self.aps as { badge?: number }).badge, undefined, "no count, no badge");
  assertEquals((testPayload().aps as { category?: string }).category, undefined, "the test has nothing to reply to");
});

Deno.test("classify and describe Apple's answers", () => {
  assertEquals(classify(200), "sent");
  assertEquals(classify(410, "Unregistered"), "gone");
  assertEquals(classify(400, "BadDeviceToken"), "gone");
  assertEquals(classify(400, "DeviceTokenNotForTopic"), "gone");
  assertEquals(classify(403, "ExpiredProviderToken"), "expired");
  assertEquals(classify(403, "InvalidProviderToken"), "config");
  assertEquals(classify(400, "TopicDisallowed"), "config");
  assertEquals(classify(429, "TooManyRequests"), "failed");
  assertEquals(classify(503, "ServiceUnavailable"), "failed");
  assertEquals(classify(0, "timed out"), "failed");
  assert(describe("config", 403, "InvalidProviderToken").includes("APNS_KEY_ID"));
  assertEquals(describe("failed", 503, null), "Apple didn't take it (HTTP 503)");
});

Deno.test("send: the right host, headers and body", async () => {
  const seen: { url: string; init: RequestInit }[] = [];
  const fake = (url: string, init: RequestInit) => {
    seen.push({ url, init });
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  const d = await send(fake, { environment: "sandbox", token: "ab12", topic: "com.bot.mcfly", jwt: "J", payload: { aps: {} }, nowSec: 100 });
  assertEquals(d, { status: 200, reason: null, outcome: "sent" });
  assertEquals(seen[0].url, "https://api.sandbox.push.apple.com/3/device/ab12");
  const h = seen[0].init.headers as Record<string, string>;
  assertEquals(h.authorization, "bearer J");
  assertEquals(h["apns-topic"], "com.bot.mcfly");
  assertEquals(h["apns-push-type"], "alert");
  assertEquals(h["apns-expiration"], String(100 + 86400));
  assertEquals(seen[0].init.body, '{"aps":{}}');
  assertEquals(apnsHost("production"), "https://api.push.apple.com");

  const refused = await send(() => Promise.resolve(new Response('{"reason":"BadDeviceToken"}', { status: 400 })),
    { environment: "production", token: "ab", topic: "t", jwt: "J", payload: {} });
  assertEquals(refused, { status: 400, reason: "BadDeviceToken", outcome: "gone" });
  const down = await send(() => Promise.reject(new TypeError("dns error")), { environment: "production", token: "ab", topic: "t", jwt: "J", payload: {} });
  assertEquals(down.outcome, "failed", "the network failing is a result, not a throw");
});

Deno.test("deliverAll makes a new provider token once when Apple calls it expired", async () => {
  const { pem } = await makeKey();
  const config = { keyId: "K", teamId: "T", privateKey: pem };
  const jwts: string[] = [];
  let first = true;
  const fake = (_url: string, init: RequestInit) => {
    jwts.push((init.headers as Record<string, string>).authorization);
    if (first) {
      first = false;
      return Promise.resolve(new Response('{"reason":"ExpiredProviderToken"}', { status: 403 }));
    }
    return Promise.resolve(new Response(null, { status: 200 }));
  };
  const targets = [
    { token: "aa", environment: "production", bundle_id: "com.bot.mcfly" },
    { token: "bb", environment: "sandbox", bundle_id: "com.bot.mcfly" },
  ];
  // Made ten minutes ago: Apple's clock thinks otherwise.
  const cache = new TokenCache();
  await cache.get(config, 5000 - 600);
  const results = await deliverAll(fake, cache, config, targets, {}, 5000);
  assertEquals(results.map((r) => r.outcome), ["sent", "sent"]);
  assertEquals(jwts.length, 3, "the first phone twice");
  assert(jwts[1] !== jwts[0], "with a new token");
  assertEquals(jwts[2], jwts[1], "which the next phone reuses");
});
