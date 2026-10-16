"use client";

import { useSyncExternalStore } from "react";
import Aurora, { glowStops, type AuroraProps } from "@/components/reactbits/Aurora";

// React Bits' Aurora (components/reactbits/Aurora.tsx) in McFly's glow: blue,
// coral and amber from the --glow-* tokens, drawn as ink on the warm canvas
// and as light on dark backgrounds. `dark` says which the page behind it is;
// left out, it follows the theme. The display draws the same curtain over its
// night-time screen saver (display/qml/components/AuroraGlow.qml).
//
// The tokens are read again when the theme, an inline style or the time of
// day's mood (data-mood) changes on <html>; Aurora glides to the new colours
// and eases between ink and light, so neither change pops.
//
// Nothing is drawn on the server: the colours come from the page's styles.

// The --glow-* tokens may transition, and then the first read still sees
// the old colour: read again when a --glow transition on <html> ends, and
// once more after the longest one we'd expect, in case none is reported.
const SETTLE_MS = 2500;
function subscribe(onChange: () => void) {
  const root = document.documentElement;
  let later = 0;
  const changed = () => {
    onChange();
    window.clearTimeout(later);
    later = window.setTimeout(onChange, SETTLE_MS);
  };
  const ended = (event: TransitionEvent) => {
    if (event.target === root && event.propertyName.startsWith("--glow")) onChange();
  };
  const observer = new MutationObserver(changed);
  observer.observe(root, { attributes: true, attributeFilter: ["class", "style", "data-mood"] });
  root.addEventListener("transitionend", ended);
  return () => {
    observer.disconnect();
    window.clearTimeout(later);
    root.removeEventListener("transitionend", ended);
  };
}
// "|" between stops: a computed colour can have spaces in it (rgb(…)).
const readStops = () => glowStops().join("|");
const readDark = () => document.documentElement.classList.contains("dark");

export function GlowAurora({ dark, ...props }: Omit<AuroraProps, "colorStops" | "lightMode"> & { dark?: boolean }) {
  const stops = useSyncExternalStore(subscribe, readStops, () => "");
  const themeDark = useSyncExternalStore(subscribe, readDark, () => false);
  if (!stops) return null;
  return <Aurora colorStops={stops.split("|")} lightMode={!(dark ?? themeDark)} {...props} />;
}
