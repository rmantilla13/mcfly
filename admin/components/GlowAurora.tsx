"use client";

import { useSyncExternalStore } from "react";
import Aurora, { glowStops, type AuroraProps } from "@/components/reactbits/Aurora";

// React Bits' Aurora (components/reactbits/Aurora.tsx) in McFly's glow: blue,
// coral and amber from the --glow-* tokens, drawn as light on the warm canvas
// and as a glow on dark backgrounds. `dark` says which the page behind it is;
// left out, it follows the theme. The display draws the same curtain over its
// night-time screen saver (display/qml/components/AuroraGlow.qml).
//
// Nothing is drawn on the server: the colours come from the page's styles.

function subscribe(onChange: () => void) {
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["class", "style"] });
  return () => observer.disconnect();
}
const readStops = () => glowStops().join(" ");
const readDark = () => document.documentElement.classList.contains("dark");

export function GlowAurora({ dark, ...props }: Omit<AuroraProps, "colorStops" | "lightMode"> & { dark?: boolean }) {
  const stops = useSyncExternalStore(subscribe, readStops, () => "");
  const themeDark = useSyncExternalStore(subscribe, readDark, () => false);
  if (!stops) return null;
  return <Aurora colorStops={stops.split(" ")} lightMode={!(dark ?? themeDark)} {...props} />;
}
