"use client";

import { useSyncExternalStore } from "react";
import ShinyText from "@/components/reactbits/ShinyText";
import styles from "./today.module.css";

// A waiting line with a slow shine passing through it (React Bits'
// ShinyText): the theme's muted ink, the full ink as the shine. ShinyText
// mixes real colours, so the two tokens are read off the page, and again
// when the theme changes; until they are known (on the server, say) it sits
// still in the token itself. A new line fades in over the old one.

function subscribe(onChange: () => void) {
  const watch = new MutationObserver(onChange);
  watch.observe(document.documentElement, { attributes: true, attributeFilter: ["class", "style"] });
  return () => watch.disconnect();
}

function inks(): string {
  const css = getComputedStyle(document.documentElement);
  return `${css.getPropertyValue("--muted-foreground").trim()}|${css.getPropertyValue("--foreground").trim()}`;
}

export function ThinkingText({ text, className }: { text: string; className?: string }) {
  const [muted, ink] = useSyncExternalStore(subscribe, inks, () => "|").split("|");
  const known = !!muted && !!ink;
  return (
    <span key={text} className={styles.fadeIn}>
      <ShinyText
        text={text}
        color={known ? muted : "var(--muted-foreground)"}
        shineColor={known ? ink : "var(--foreground)"}
        speed={2.2}
        disabled={!known}
        className={className}
      />
    </span>
  );
}
