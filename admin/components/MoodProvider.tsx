"use client";

import { useEffect } from "react";
import { moodAt } from "@/lib/mood";

// Keeps the display's time of day on <html> as data-mood (lib/mood.ts), so
// globals.css can swap the glow to the mood's colours. The root layout's
// MOOD_SCRIPT sets it before the first paint; this keeps it current. Set in
// an effect, never during render: the server sends no attribute (the day
// palette) and can't know the viewer's clock.
//
// Which clock: the root layout mounts one with no zone, and it uses the
// browser's, since the layout can't read the settings (the sign-in page has
// nobody signed in to read them as). Pages that already loaded the display's
// zone (Today and Ambient, TodayData.timeZone) mount their own with it, and a
// zone given that way wins over the browser's for as long as the page is up;
// where the two zones differ, the page turns once it has hydrated. All of
// them share one timer, re-checked on each minute (the moods turn on whole
// or half hours in every zone) and when the tab comes back.

type Entry = { timeZone?: string };

const entries: Entry[] = [];
let timer: ReturnType<typeof setTimeout> | undefined;

function apply() {
  const zone = entries.findLast((e) => e.timeZone)?.timeZone;
  document.documentElement.dataset.mood = moodAt(Date.now(), zone);
}

function schedule() {
  clearTimeout(timer);
  timer = setTimeout(
    () => {
      apply();
      schedule();
    },
    60_000 - (Date.now() % 60_000) + 20,
  );
}

function onVisible() {
  if (!document.hidden) apply();
}

export function MoodProvider({ timeZone }: { timeZone?: string }) {
  useEffect(() => {
    // An object per mount, so a remount (React runs effects twice in
    // development) never removes another instance's zone.
    const entry: Entry = { timeZone };
    entries.push(entry);
    if (entries.length === 1) document.addEventListener("visibilitychange", onVisible);
    apply();
    schedule();
    return () => {
      entries.splice(entries.indexOf(entry), 1);
      if (entries.length) {
        apply();
        return;
      }
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
      delete document.documentElement.dataset.mood;
    };
  }, [timeZone]);
  return null;
}
