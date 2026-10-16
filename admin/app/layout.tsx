import type { Metadata, Viewport } from "next";
import { MoodProvider } from "@/components/MoodProvider";
import { MOOD_SCRIPT } from "@/lib/mood";
import { ThemeProvider } from "@/components/ThemeProvider";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { inter } from "./fonts";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "McFly Console", template: "%s · McFly Console" },
  description: "The admin console for McFly.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f1efeb" },
    { media: "(prefers-color-scheme: dark)", color: "#121214" },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    // next-themes sets the .dark class on <html> before paint, and the mood
    // script data-mood, which React can't know about at hydration; hence
    // suppressHydrationWarning.
    <html lang="en" className={inter.variable} suppressHydrationWarning>
      <head>
        {/* The display's time of day as data-mood on <html> before the first
            paint, in this browser's zone, so a page never opens on the day
            glow and then turns (lib/mood.ts). The layout can't read the
            display's zone: the sign-in page has nobody to read it as. */}
        <script dangerouslySetInnerHTML={{ __html: MOOD_SCRIPT }} />
      </head>
      <body>
        {/* Keeps it current on the minute; Today and Ambient know the
            display's zone and say so with theirs (components/MoodProvider.tsx). */}
        <MoodProvider />
        <ThemeProvider>
          <TooltipProvider>{children}</TooltipProvider>
          <Toaster position="bottom-center" />
        </ThemeProvider>
      </body>
    </html>
  );
}
