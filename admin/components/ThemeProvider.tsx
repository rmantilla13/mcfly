"use client";

import { ThemeProvider as NextThemes } from "next-themes";
import type { ReactNode } from "react";

// Dark mode follows the system: next-themes reads prefers-color-scheme and
// puts .dark on <html>, which is what globals.css and every shadcn
// component key off. There is no toggle in the console; the display and the
// app follow the system too.
export function ThemeProvider({ children }: { children: ReactNode }) {
  return (
    <NextThemes attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
      {children}
    </NextThemes>
  );
}
