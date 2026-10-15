import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  // public/voice-runtime holds the ONNX runtime copied from node_modules.
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts", "public/voice-runtime/**"]),
]);
