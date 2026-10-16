"use client";

import { Fragment, useState } from "react";
import { nextStream, streamWords } from "@/lib/today";
import styles from "./today.module.css";

// An answer arriving word by word: each new word comes into focus as it
// lands, and the ones already there stay put (they keep their keys). When
// the finished text isn't a continuation of what streamed (the assistant's
// last word replacing it, a refusal say), the whole text is laid in again.
// `still` shows a text that didn't just arrive (a saved one) as it is.

export function StreamingText({ text, still = false, className }: { text: string; still?: boolean; className?: string }) {
  const [shown, setShown] = useState({ text: "", gen: 0 });
  const next = nextStream(shown, text);
  // Adjusting state to a new prop during render, as React suggests, rather
  // than in an effect a frame late.
  if (next !== shown) setShown(next);
  if (still) return <span className={className}>{text}</span>;
  return (
    <span className={className}>
      {streamWords(next.text).map((token, i) => {
        const [, lead, word, trail] = /^(\s*)(\S+)(\s*)$/.exec(token) ?? ["", "", token, ""];
        return (
          <Fragment key={`${next.gen}:${i}`}>
            {lead}
            {/* inline-block, so the word can move as it fades in; the
                spaces stay outside it so the line still wraps on them. */}
            <span className={`inline-block ${styles.word}`}>{word}</span>
            {trail}
          </Fragment>
        );
      })}
    </span>
  );
}
