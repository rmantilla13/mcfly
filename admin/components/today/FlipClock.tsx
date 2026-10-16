"use client";

import { cn } from "cn";
import SplitFlapText from "@/components/reactbits/SplitFlapText";

// A clock whose digits flip when they change, like a split-flap board without
// the tiles (React Bits' SplitFlapText, "minimal" style): the old digit folds
// away along a hairline as the new one drops in. The hours and the minutes are
// separate boards, so the colon keeps its own narrow width; the type is the
// surrounding text's (size, weight, colour). The tiles are as wide as Inter's
// tabular digits less the clock's -0.04em tracking, so the digits sit where
// plain text would put them.
const BOARD = {
  tileStyle: "minimal",
  fontSize: "1em",
  tileWidth: "0.567em",
  gap: 0,
  padTo: 0,
  intro: false,
  charset: "numeric",
  flipsPerChar: 0,
  flipDuration: 0.55,
  stagger: 0.09,
  depth: 0,
  textColor: "currentColor",
  style: { fontFamily: "inherit", fontWeight: "inherit", letterSpacing: "inherit", lineHeight: "inherit" },
} as const;

export function FlipClock({ time, className }: { time: string; className?: string }) {
  const [hours, minutes = ""] = time.split(":");
  return (
    <span className={cn("inline-flex items-center tabular-nums", className)}>
      {/* The boards' glyphs are drawn out of flow, so they give the line no
          baseline; this empty run does, at the same height as the digits, so
          "AM"/"PM" beside the clock still sits on it. */}
      <span aria-hidden="true">{"\u200b"}</span>
      <span className="sr-only" suppressHydrationWarning>
        {time}
      </span>
      <SplitFlapText text={hours} {...BOARD} aria-hidden="true" />
      <span aria-hidden="true">:</span>
      <SplitFlapText text={minutes} {...BOARD} aria-hidden="true" />
    </span>
  );
}
