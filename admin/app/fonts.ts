import localFont from "next/font/local";

// Inter (variable), self-hosted from @fontsource-variable/inter so builds
// never need the network.
export const inter = localFont({
  src: "../node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
  weight: "100 900",
  style: "normal",
  display: "swap",
  variable: "--font-inter",
  fallback: ["system-ui", "-apple-system", "Segoe UI", "Roboto", "Helvetica Neue", "Arial", "sans-serif"],
});

// The wordmark's face, Exo 2 Black Italic (SIL OFL, _fonts/OFL.txt): the
// boot clip's, the display's and the apps' "McFly".
export const wordmark = localFont({
  src: "./_fonts/Exo2-BlackItalic.ttf",
  weight: "900",
  style: "italic",
  display: "swap",
  fallback: ["system-ui", "sans-serif"],
});
