// Apple's push service, for the notify function: the provider token (an
// ES256 JWT signed with the team's .p8 key), a message's notification, and
// what Apple's answer means for the token. Pure apart from `send`, which
// takes its fetch, so apns.test.ts runs without the network.
//
// Secrets: APNS_KEY_ID (the key's 10-character id), APNS_TEAM_ID (the
// developer team) and APNS_PRIVATE_KEY (the .p8 file's text; literal \n,
// or the whole file in base64, also do).

export type ApnsConfig = { keyId: string; teamId: string; privateKey: string };

export function apnsConfig(env: (name: string) => string | undefined): ApnsConfig | null {
  const keyId = (env("APNS_KEY_ID") ?? "").trim();
  const teamId = (env("APNS_TEAM_ID") ?? "").trim();
  const privateKey = (env("APNS_PRIVATE_KEY") ?? "").trim();
  if (!keyId || !teamId || !privateKey) return null;
  return { keyId, teamId, privateKey };
}

const b64 = (bytes: Uint8Array): string => {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
};
const b64url = (bytes: Uint8Array): string => b64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const fromB64 = (text: string): Uint8Array<ArrayBuffer> => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

// The key's PKCS#8 bytes from the .p8 text as it was pasted: the PEM, the
// PEM with its line breaks written \n, the PEM in base64, or the bare body.
export function pkcs8FromP8(text: string): Uint8Array<ArrayBuffer> {
  let pem = text.trim().replace(/\\n/g, "\n");
  if (!pem.includes("-----BEGIN")) {
    try {
      const decoded = new TextDecoder().decode(fromB64(pem.replace(/\s+/g, "")));
      if (decoded.includes("-----BEGIN")) pem = decoded;
    } catch {
      // Not base64 of a PEM: take it as the body itself.
    }
  }
  const body = pem.replace(/-----(BEGIN|END)[^-]*-----/g, "").replace(/\s+/g, "");
  if (!body) throw new Error("APNS_PRIVATE_KEY holds no key");
  try {
    return fromB64(body);
  } catch {
    throw new Error("APNS_PRIVATE_KEY isn't a .p8 key");
  }
}

export async function importP8(text: string): Promise<CryptoKey> {
  const der = pkcs8FromP8(text);
  return await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

// The provider token Apple wants on every request: header { alg ES256, kid },
// claims { iss: team, iat }. WebCrypto's ECDSA signature is already the raw
// r‖s a JWS takes.
export async function providerToken(config: ApnsConfig, key: CryptoKey, nowSec: number): Promise<string> {
  const enc = new TextEncoder();
  const head = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: config.teamId, iat: Math.floor(nowSec) })));
  const input = `${head}.${claims}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(input));
  return `${input}.${b64url(new Uint8Array(sig))}`;
}

// One token for 50 minutes: Apple refuses one older than an hour, and one
// made more often than every 20 minutes (TooManyProviderTokenUpdates).
export class TokenCache {
  private token: string | null = null;
  private madeAt = 0;
  private key: CryptoKey | null = null;
  private keyText = "";
  constructor(private readonly lifetimeSec = 50 * 60) {}

  async get(config: ApnsConfig, nowSec: number): Promise<string> {
    if (this.token && this.keyText === config.privateKey + config.keyId + config.teamId && nowSec - this.madeAt < this.lifetimeSec) {
      return this.token;
    }
    if (!this.key || this.keyText !== config.privateKey + config.keyId + config.teamId) {
      this.key = await importP8(config.privateKey);
      this.keyText = config.privateKey + config.keyId + config.teamId;
    }
    this.token = await providerToken(config, this.key, nowSec);
    this.madeAt = nowSec;
    return this.token;
  }

  // Apple called it expired: the next get() makes a new one.
  forget(): void {
    this.token = null;
  }
}

export const apnsHost = (environment: string): string =>
  environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";

// A display's message, as message_push() has it.
export type PushMessage = {
  id: string;
  sender_name: string;
  body: string;
  created_at?: string;
  device_name?: string | null;
  displays?: number;
  unread?: number;
};

export const MESSAGE_CATEGORY = "MCFLY_MESSAGE";
export const MESSAGE_THREAD = "mcfly-messages";

// The notification: who wrote as the title, the display under it when there
// is more than one and someone at home picked their name, the message, and
// the unread count on the app's icon. The category carries the Reply action;
// the thread groups them; message_id lets the app open the thread.
export function messagePayload(m: PushMessage): Record<string, unknown> {
  const alert: Record<string, string> = { title: m.sender_name, body: m.body };
  if ((m.displays ?? 1) > 1 && m.device_name && m.device_name !== m.sender_name) alert.subtitle = m.device_name;
  const aps: Record<string, unknown> = {
    alert,
    sound: "default",
    "thread-id": MESSAGE_THREAD,
    category: MESSAGE_CATEGORY,
  };
  if (typeof m.unread === "number" && m.unread >= 0) aps.badge = m.unread;
  return { aps, message_id: m.id };
}

// What the test action sends: the same look, nothing to reply to.
export function testPayload(): Record<string, unknown> {
  return {
    aps: {
      alert: { title: "McFly", body: "Notifications work: messages from home will show up here." },
      sound: "default",
      "thread-id": MESSAGE_THREAD,
    },
  };
}

// What Apple's answer means: sent; gone (the token is no good: forget it);
// expired (our provider token: make a new one and try again); config (the
// key, team or topic is wrong: every token would fail the same way); or
// failed (this one didn't go, for now).
export type Outcome = "sent" | "gone" | "expired" | "config" | "failed";

export function classify(status: number, reason?: string | null): Outcome {
  if (status === 200) return "sent";
  if (status === 410) return "gone";
  if (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic")) return "gone";
  if (status === 403 && reason === "ExpiredProviderToken") return "expired";
  if (status === 403 || reason === "TopicDisallowed" || reason === "BadTopic" || reason === "MissingTopic") return "config";
  return "failed";
}

// A sentence for the display and the logs, from Apple's reason.
export function describe(outcome: Outcome, status: number, reason?: string | null): string {
  if (outcome === "config") {
    if (reason === "InvalidProviderToken") return "Apple refused the push key: check APNS_KEY_ID, APNS_TEAM_ID and APNS_PRIVATE_KEY";
    if (reason === "TopicDisallowed" || reason === "BadTopic" || reason === "MissingTopic" || reason === "DeviceTokenNotForTopic") {
      return "Apple refused the app's bundle id for this push key";
    }
    return `Apple refused the push key (${reason ?? status})`;
  }
  if (outcome === "gone") return "the phone's notification token is no longer good";
  return `Apple didn't take it (${reason ?? `HTTP ${status}`})`;
}

export type Delivery = { status: number; reason: string | null; outcome: Outcome };

type Fetch = (input: string, init: RequestInit) => Promise<Response>;

// Sends one notification to one phone. A network failure is "failed", never
// a throw, so one phone can't stop the others.
export async function send(
  fetchFn: Fetch,
  opts: { environment: string; token: string; topic: string; jwt: string; payload: unknown; timeoutMs?: number; nowSec?: number },
): Promise<Delivery> {
  const now = opts.nowSec ?? Date.now() / 1000;
  try {
    const res = await fetchFn(`${apnsHost(opts.environment)}/3/device/${opts.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${opts.jwt}`,
        "apns-topic": opts.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        // Kept for a day if the phone is off, then dropped.
        "apns-expiration": String(Math.floor(now) + 24 * 3600),
        "content-type": "application/json",
      },
      body: JSON.stringify(opts.payload),
      signal: AbortSignal.timeout(opts.timeoutMs ?? 10_000),
    });
    let reason: string | null = null;
    if (res.status !== 200) {
      const text = await res.text().catch(() => "");
      try {
        reason = (JSON.parse(text) as { reason?: string }).reason ?? null;
      } catch {
        reason = text.slice(0, 80) || null;
      }
    } else {
      await res.body?.cancel().catch(() => {});
    }
    return { status: res.status, reason, outcome: classify(res.status, reason) };
  } catch (e) {
    return { status: 0, reason: e instanceof Error ? e.message.slice(0, 120) : "unreachable", outcome: "failed" };
  }
}

export type Target = { token: string; environment: string; bundle_id: string };
export type Result = Target & Delivery;

// Sends `payload` to each phone in turn with one provider token, made anew
// once if Apple calls it expired.
export async function deliverAll(
  fetchFn: Fetch,
  cache: TokenCache,
  config: ApnsConfig,
  targets: Target[],
  payload: unknown,
  nowSec = Date.now() / 1000,
): Promise<Result[]> {
  const out: Result[] = [];
  let jwt = await cache.get(config, nowSec);
  for (const t of targets) {
    const opts = { environment: t.environment, token: t.token, topic: t.bundle_id, payload, nowSec };
    let d = await send(fetchFn, { ...opts, jwt });
    if (d.outcome === "expired") {
      cache.forget();
      jwt = await cache.get(config, nowSec);
      d = await send(fetchFn, { ...opts, jwt });
    }
    out.push({ ...t, ...d });
  }
  return out;
}
