// Pairing's small rules, kept out of index.ts so they can be unit-tested
// (pairing.test.ts).

export const CODE = /^[0-9]{6}$/;
export const SECRET_HASH = /^[0-9a-f]{64}$/;

/** A six-digit code from the system's randomness. */
export function randomCode(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
}

/** The display's name as the admin typed it, or the default. */
export function deviceName(value: unknown): string {
  const name = typeof value === "string" ? value.trim().slice(0, 80) : "";
  return name || "Display";
}
