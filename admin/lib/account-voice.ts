// The voice McFly speaks with is one choice for the account: the Pi, the web
// and the iPhone/Mac all follow it. It lives in the displays' settings
// (devices.settings.voice), which the Pi already syncs both ways; the console
// and the app read it from admin_list_devices and write it to every display.
// "This device's voice" (the browser's own) is the one local exception: it is
// kept in this browser and never sent. Pure, so tests/account-voice.test.mjs
// can check it.

export const KOKORO_VOICES = ["af_heart", "af_bella", "am_michael", "am_fenrir"] as const;
export type KokoroVoice = (typeof KOKORO_VOICES)[number];

export const isKokoroVoice = (v: unknown): v is KokoroVoice => typeof v === "string" && (KOKORO_VOICES as readonly string[]).includes(v);

// The account's voice: the first display (admin_list_devices' order, oldest
// first) that has one. null with no display, or none with a voice yet.
export function accountVoice(devices: { settings?: { voice?: unknown } | null }[]): KokoroVoice | null {
  for (const d of devices) {
    const v = d.settings?.voice;
    if (isKokoroVoice(v)) return v;
  }
  return null;
}

// What this browser speaks with: "system" stays put (a per-device choice),
// anything else follows the account once it's known.
export function followVoice<T extends string>(local: T, account: KokoroVoice | null): T | KokoroVoice {
  if (local === "system" || !account) return local;
  return account;
}
