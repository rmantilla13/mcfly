"use client";

import { cn } from "cn";
import { useEffect, useState, type CSSProperties } from "react";
import { makeParticles, weatherCount, weatherFor, type Particle, type WeatherKind, type WeatherPref } from "@/lib/weather";
import styles from "./AmbientWeather.module.css";

// Weather over the ambient view's backdrop, under its words: the display's
// choice (Displays → Customize → Weather), as its saver draws it
// (display/qml/components/Weather.qml). Snow, petals, fireflies or leaves,
// "season" picking by the date where the display is (the account's zone).
//
// Each particle is a span the stylesheet animates by transform and opacity,
// so the compositor moves them and no script runs per frame; the page stays
// up all night at nothing more than that. Built on the client only (they are
// random), again when the window changes size, and not at all with reduced
// motion asked for.
export function AmbientWeather({ pref, nowMs, timeZone, className }: { pref: WeatherPref; nowMs: number; timeZone: string; className?: string }) {
  const kind = weatherFor(pref, nowMs, timeZone);
  const [scene, setScene] = useState<{ kind: WeatherKind; particles: Particle[] } | null>(null);

  useEffect(() => {
    const still = window.matchMedia("(prefers-reduced-motion: reduce)");
    let timer = 0;
    const make = () => {
      if (!kind || still.matches) return setScene(null);
      setScene({ kind, particles: makeParticles(kind, weatherCount(kind, window.innerWidth, window.innerHeight)) });
    };
    make();
    // A tablet turned, a window resized: a new count for the new size.
    const later = () => {
      window.clearTimeout(timer);
      timer = window.setTimeout(make, 400);
    };
    window.addEventListener("resize", later);
    still.addEventListener("change", make);
    return () => {
      window.clearTimeout(timer);
      window.removeEventListener("resize", later);
      still.removeEventListener("change", make);
    };
  }, [kind]);

  if (!scene) return null;
  return (
    <div className={cn(styles.weather, styles[scene.kind], className)} aria-hidden="true">
      {scene.particles.map((p, i) => (
        <Drop key={i} kind={scene.kind} p={p} />
      ))}
    </div>
  );
}

function Drop({ kind, p }: { kind: WeatherKind; p: Particle }) {
  const tone = styles[`tone${p.tone}`];
  if (kind === "fireflies")
    return (
      <span
        className={cn(styles.p, tone)}
        style={
          {
            "--size": `${p.size}px`,
            "--x0": `${p.xs[0]}vw`, "--x1": `${p.xs[1]}vw`, "--x2": `${p.xs[2]}vw`, "--x3": `${p.xs[3]}vw`,
            "--y0": `${p.ys[0]}vh`, "--y1": `${p.ys[1]}vh`, "--y2": `${p.ys[2]}vh`, "--y3": `${p.ys[3]}vh`,
            "--dur": `${p.dur}s`, "--delay": `${p.delay}s`,
            "--glow-dur": `${p.swayDur}s`, "--glow-delay": `${p.swayDelay}s`,
          } as CSSProperties
        }
      />
    );
  const fall = { "--x": `${p.x}vw`, "--drift": `${p.drift}vw`, "--dur": `${p.dur}s`, "--delay": `${p.delay}s` };
  const sway = { "--size": `${p.size}px`, "--alpha": p.alpha, "--sway": `${p.sway}px`, "--sway-dur": `${p.swayDur}s`, "--sway-delay": `${p.swayDelay}s` };
  // A flake only falls and sways: one element. A petal or a leaf also spins
  // and tumbles, which would turn its sway with it, so its fall is an element
  // of its own around the one that swings.
  if (kind === "snow") return <span className={styles.p} style={{ ...fall, ...sway } as CSSProperties} />;
  return (
    <span className={styles.p} style={fall as CSSProperties}>
      <span
        className={cn(styles.shape, tone)}
        style={
          {
            ...sway,
            "--flip-k": p.flipK, "--flip-dur": `${p.flipDur}s`, "--flip-delay": `${p.flipDelay}s`,
            "--spin-from": `${p.spinFrom}deg`, "--spin-to": `${p.spinTo}deg`, "--spin-dur": `${p.spinDur}s`, "--spin-delay": `${p.spinDelay}s`,
          } as CSSProperties
        }
      />
    </span>
  );
}
