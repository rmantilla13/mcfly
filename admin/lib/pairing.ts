// The 6-digit pairing code a display shows (backend/supabase/functions/
// pair-device/pairing.ts: CODE). The console reads it from ?code= on /pair
// and from a text field, so both go through here before anything renders or
// sends it. Pure, so tests/pairing.test.mjs can check it.

export const CODE_LENGTH = 6;

// Digits only, at most six of them; anything else in the input is dropped.
// "12 34-56" → "123456", "<script>" → "".
export function sanitizeCode(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replace(/\D/g, "").slice(0, CODE_LENGTH);
}

export function isCompleteCode(value: string): boolean {
  return /^[0-9]{6}$/.test(value);
}

// "123 456", for showing a code back to the admin.
export function formatCode(code: string): string {
  return isCompleteCode(code) ? `${code.slice(0, 3)} ${code.slice(3)}` : code;
}
