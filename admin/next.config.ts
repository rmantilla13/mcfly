import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The console is private: never framed, never indexed, no referrer leaks.
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "same-origin" },
          { key: "X-Robots-Tag", value: "noindex, nofollow" },
        ],
      },
    ];
  },
  poweredByHeader: false,
  // The console is a folder in a bigger repo; without this Turbopack guesses
  // the workspace root from whatever lockfile it finds above it.
  turbopack: { root: import.meta.dirname },
  // next dev would otherwise write AGENTS.md and CLAUDE.md into this folder.
  agentRules: false,
};

export default nextConfig;
