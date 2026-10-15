// Copies the ONNX runtime that the Kokoro voice runs on (WebAssembly and its
// loader, from @huggingface/transformers) into public/voice-runtime/, so the
// browser loads it from McFly itself instead of a public CDN. Runs before
// `next dev` and `next build` (package.json); the copies aren't in git.
import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const from = join(root, "node_modules/@huggingface/transformers/dist");
const to = join(root, "public/voice-runtime");
const files = ["ort-wasm-simd-threaded.jsep.mjs", "ort-wasm-simd-threaded.jsep.wasm"];

mkdirSync(to, { recursive: true });
for (const f of files) {
  if (!existsSync(join(from, f))) {
    console.warn(`voice runtime: ${f} is missing (npm install?); the web voice falls back to the browser's own`);
    continue;
  }
  copyFileSync(join(from, f), join(to, f));
}
