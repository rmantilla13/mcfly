"use client";

import Link from "next/link";
import { useId } from "react";
import { wordmark } from "@/app/fonts";
import { cn } from "cn";

// The McFly mark, the flux capacitor's Y, as in app/icon.svg (the numbers of
// display/qml/components/FluxMark.qml on a 64 box). Ids are per copy: the
// header and a sheet can show it at once.
export function BrandMark({ className }: { className?: string }) {
  const id = useId();
  const arms = [
    { d: "M24.24 29.44 12.05 22.4", from: [12.05, 22.4], to: [24.24, 29.44], outer: "#5B7CF5", inner: "#B5C4FA" },
    { d: "M39.76 29.44 51.95 22.4", from: [51.95, 22.4], to: [39.76, 29.44], outer: "#F07F5A", inner: "#F8C5B5" },
    { d: "M32 42.88v14.08", from: [32, 56.96], to: [32, 42.88], outer: "#F6B94A", inner: "#FBE0AE" },
  ];
  return (
    <svg viewBox="0 0 64 64" className={cn("size-9 shrink-0", className)} aria-hidden="true">
      <defs>
        <clipPath id={`${id}t`}>
          <rect width="64" height="64" rx="16.64" />
        </clipPath>
        <linearGradient id={`${id}b`} x1="0" y1="0" x2="0" y2="64" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#30323A" />
          <stop offset="1" stopColor="#121317" />
        </linearGradient>
        {arms.map((a, i) => (
          <linearGradient key={i} id={`${id}a${i}`} x1={a.from[0]} y1={a.from[1]} x2={a.to[0]} y2={a.to[1]} gradientUnits="userSpaceOnUse">
            <stop offset="0" stopColor={a.outer} />
            <stop offset="1" stopColor={a.inner} />
          </linearGradient>
        ))}
        <filter id={`${id}g`} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="3.84" />
        </filter>
        <filter id={`${id}c`} x="-100%" y="-100%" width="300%" height="300%">
          <feGaussianBlur stdDeviation="5.12" />
        </filter>
      </defs>
      <g clipPath={`url(#${id}t)`} strokeLinecap="round" strokeWidth="7.68">
        <rect width="64" height="64" fill={`url(#${id}b)`} />
        <g filter={`url(#${id}g)`}>
          {arms.map((a, i) => (
            <path key={i} d={a.d} stroke={a.outer} />
          ))}
        </g>
        {arms.map((a, i) => (
          <path key={i} d={a.d} stroke={`url(#${id}a${i})`} />
        ))}
        <circle cx="32" cy="33.92" r="4.8" fill="#fff" filter={`url(#${id}c)`} />
        <circle cx="32" cy="33.92" r="4.8" fill="#fff" />
      </g>
    </svg>
  );
}

// "McFly" in the logo's face, Exo 2 Black Italic, as the display and the apps set it.
export function Wordmark({ className }: { className?: string }) {
  return <span className={cn(wordmark.className, "tracking-normal", className)}>McFly</span>;
}

export function Brand({ role = "Console" }: { role?: string }) {
  return (
    <Link href="/" className="flex items-center gap-3 rounded-lg px-2 py-1 text-foreground no-underline">
      <BrandMark />
      <span className="grid leading-tight">
        <Wordmark className="text-[19px]" />
        <span className="text-xs font-semibold tracking-wider text-muted-foreground uppercase">{role}</span>
      </span>
    </Link>
  );
}
