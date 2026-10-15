// A reply cut into pieces short enough to synthesize quickly, so the first
// one starts playing while the rest are rendered (as Homestead did). Pure,
// so tests/sentences.test.mjs can check it.

const MAX = 220;

export function speechPieces(text: string): string[] {
  const clean = text
    .replace(/https?:\/\/\S+/g, "a link")
    .replace(/[*_#`>[\]]/g, "")
    .replace(/\(([^)]*)\)/g, ", $1,")
    .replace(/\s+/g, " ")
    .trim();
  if (!clean) return [];
  const sentences = clean.match(/[^.!?…]+(?:[.!?…]+["”’)]*|$)/g)?.map((s) => s.trim()).filter(Boolean) ?? [clean];
  const pieces: string[] = [];
  for (const s of sentences) {
    // A long sentence splits at commas, then words.
    if (s.length <= MAX) {
      pieces.push(s);
      continue;
    }
    let current = "";
    for (const part of s.split(/(?<=[,;:])\s+/)) {
      for (const word of part.length > MAX ? part.split(" ") : [part]) {
        if ((current + " " + word).trim().length > MAX && current) {
          pieces.push(current.trim());
          current = "";
        }
        current += " " + word;
      }
    }
    if (current.trim()) pieces.push(current.trim());
  }
  // Very short pieces ride along with the next one, so speech doesn't stutter.
  const merged: string[] = [];
  for (const p of pieces) {
    const last = merged.at(-1);
    if (last && last.length < 40 && (last + " " + p).length <= MAX) merged[merged.length - 1] = `${last} ${p}`;
    else merged.push(p);
  }
  return merged;
}
