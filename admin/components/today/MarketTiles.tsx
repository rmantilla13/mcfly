import { cn } from "cn";
import { ChartSplineIcon } from "lucide-react";
import Link from "next/link";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { Sparkline } from "@/components/charts/Sparkline";
import type { TodayTicker } from "@/lib/today";
import { Tile, TileHead } from "./Tile";

// Markets as small tiles: the symbol and today's move, the last thirty
// points (the display's sparkline) and the price, which counts to its new
// value when a refresh brings one. Each goes to the Markets tab.

// Four across fill the tile; five or six read better three by two.
const COLS: Record<number, string> = { 1: "sm:grid-cols-1", 2: "sm:grid-cols-2", 3: "sm:grid-cols-3", 4: "sm:grid-cols-4" };

export function MarketTiles({ tickers, index, className }: { tickers: TodayTicker[]; index: number; className?: string }) {
  return (
    <Tile index={index} label="Markets" className={cn("gap-4 p-5", className)}>
      <TileHead
        icon={<ChartSplineIcon />}
        action={
          <Link href="/feed?tab=markets" className="text-[13px] font-medium text-muted-foreground no-underline hover:text-foreground">
            All markets
          </Link>
        }
      >
        Markets
      </TileHead>
      {/* The tiles fill the height the row gives them; the lines take the room. */}
      <div className={cn("grid flex-1 grid-cols-2 gap-2.5", COLS[tickers.length] ?? "sm:grid-cols-3")}>
        {tickers.map((t) => {
          const tone = t.direction === "up" ? "up" : t.direction === "down" ? "down" : "neutral";
          return (
            <Link
              key={t.symbol}
              href="/feed?tab=markets"
              className="flex min-w-0 flex-col gap-1 rounded-[20px] bg-muted/70 p-3.5 text-foreground no-underline ring-1 ring-foreground/[0.04] transition-colors outline-none hover:ring-foreground/15 focus-visible:ring-2 focus-visible:ring-ring"
            >
              <span className="flex items-center gap-2">
                <strong className="text-[15px] font-semibold">{t.symbol}</strong>
                <span
                  className={cn(
                    "ml-auto rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums",
                    tone === "up" && "bg-success/12 text-success",
                    tone === "down" && "bg-destructive/10 text-destructive",
                    tone === "neutral" && "bg-foreground/8 text-muted-foreground",
                  )}
                >
                  {t.change}
                </span>
              </span>
              {t.name && t.name !== t.symbol ? <span className="truncate text-[13px] text-muted-foreground">{t.name}</span> : null}
              {t.points.length > 1 ? (
                <Sparkline points={t.points} tone={tone} className="mt-auto mb-1.5 h-auto max-h-20 min-h-9 flex-1" label={`${t.symbol}, last ${t.points.length} readings`} />
              ) : (
                <span className="mt-auto min-h-9" />
              )}
              <span className="text-xl font-semibold tracking-tight tabular-nums">
                {t.value != null ? <AnimatedNumber value={t.value} format="price" currency={t.currency ?? undefined} /> : t.price}
              </span>
            </Link>
          );
        })}
      </div>
    </Tile>
  );
}
