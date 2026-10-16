import { cn } from "cn";
import { ArrowDownRightIcon, ArrowUpRightIcon, EyeIcon, TrendingUpIcon } from "lucide-react";
import type { CSSProperties } from "react";
import { AnimatedNumber } from "@/components/AnimatedNumber";
import { AgentLabel, EmptyState, Time } from "@/components/bits";
import { AreaChart, Sparkline } from "@/components/charts";
import { AskLink, ChangeChip, Footnote } from "@/components/feed/bits";
import { CARD, rise } from "@/components/feed/styles";
import { listQuoteData } from "@/lib/data";
import { formatPrice } from "@/lib/format";
import { buildHoldings, type Holding, type Insight, type Portfolio, sharesLabel, type Signal, signedPct, signedPrice } from "@/lib/holdings";
import { BIG_MOVE_PCT, SWING_RATIO } from "@/lib/insights";
import { downsample, rangeOf, type SeriesPoint, withLatest } from "@/lib/series";
import { type TodayTicker, toTicker } from "@/lib/today";
import type { QuoteRow } from "@/lib/types";

// The Markets tab as cards: the holdings first when an agent sends them (the
// total, today's move and the gain, then each position by size); the first
// symbol in the display's order large, with its month as an area chart (in
// the brand blue: a month isn't today's move) and where today sits in that
// range; a card on the day's moves (how many rose, each symbol's move against
// the others, the biggest one against its usual swing); then a card per
// symbol with its price, today's move and a 30-day line, coloured by today's
// move as on the display's Markets screen, with the holding and the signals
// its agent sent (lib/holdings.ts). Hidden symbols are left to the Manage view.

const HERO_POINTS = 60;
const DAY = 86_400_000;

type Card = { q: QuoteRow & { price: number }; t: TodayTicker; history: SeriesPoint[]; insight?: Insight };

const tone = (d: TodayTicker["direction"]) => (d === "up" ? "up" : d === "down" ? "down" : "neutral");
const chipTone = (d: TodayTicker["direction"]) => (d === "up" ? "good" : d === "down" ? "bad" : "neutral");
const moveClass = (n: number | null) => (n == null || n === 0 ? "text-muted-foreground" : n > 0 ? "text-success" : "text-destructive");

export async function MarketsGrid({ quotes, series, timeZone }: { quotes: QuoteRow[]; series: Record<string, SeriesPoint[]>; timeZone: string }) {
  // The extras are optional: without them the prices still show.
  const { insights, portfolio } = buildHoldings(quotes, await listQuoteData().catch(() => []));
  const cards: Card[] = quotes
    .filter((q): q is QuoteRow & { price: number } => !q.hidden && q.price != null)
    .map((q) => {
      const history = withLatest(series[q.symbol] ?? [], q.as_of, q.price);
      return { q, t: toTicker(q, history, timeZone), history, insight: insights[q.symbol] };
    });
  const hidden = quotes.filter((q) => q.hidden);
  const waiting = quotes.filter((q) => !q.hidden && q.price == null);

  if (cards.length === 0) {
    return (
      <EmptyState title={quotes.length ? "Every symbol is hidden" : "No symbols"} icon={<TrendingUpIcon />}>
        {quotes.length
          ? "Manage shows them all; switch one back on to see it here and on the display."
          : "Every symbol an agent pushes (POST /ingest/quotes) shows up here, in the order the display shows it."}
      </EmptyState>
    );
  }

  const [hero, ...rest] = cards;
  const lead = portfolio.count ? 1 : 0;
  return (
    <>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {portfolio.count ? <HoldingsCard portfolio={portfolio} cards={cards} /> : null}
        <HeroCard card={hero} timeZone={timeZone} index={lead} />
        <MovesCard cards={cards} index={lead + 1} />
        {rest.map((card, i) => (
          <SymbolCard key={card.q.symbol} card={card} index={lead + i + 2} />
        ))}
      </div>
      {hidden.length || waiting.length ? (
        <Footnote>
          {hidden.length ? <>Hidden from the display: {hidden.map((q) => q.symbol).join(", ")}. </> : null}
          {waiting.length ? <>No quote yet: {waiting.map((q) => q.symbol).join(", ")}. </> : null}
          Manage lists every symbol.
        </Footnote>
      ) : null}
    </>
  );
}

// The holdings summed, then each position by size: shares, value, its share
// of the total as a bar, and its gain since bought.
function HoldingsCard({ portfolio, cards }: { portfolio: Portfolio; cards: Card[] }) {
  const rows = cards
    .flatMap((c) => (c.insight?.holding ? [{ c, h: c.insight.holding }] : []))
    .sort((a, b) => b.h.value - a.h.value);
  const r = rise(0);
  return (
    <article className={cn(CARD, "flex flex-col gap-5 p-6 sm:col-span-2 lg:col-span-3 max-sm:p-5", r.className)} style={r.style}>
      <div className="flex flex-wrap items-end gap-x-10 gap-y-4">
        <div>
          <h3 className="text-sm font-medium text-muted-foreground">{portfolio.count === 1 ? "Your holding" : `Your ${portfolio.count} holdings`}</h3>
          <div className="mt-2 font-heading text-[36px] leading-none font-semibold tracking-tight tabular-nums max-sm:text-[30px]">
            <AnimatedNumber value={portfolio.value} format="price" />
          </div>
        </div>
        {portfolio.dayChange != null ? (
          <Move label="Today" amount={signedPrice(portfolio.dayChange, "USD")} pct={portfolio.dayChangePct} digits={2} value={portfolio.dayChange} />
        ) : null}
        {portfolio.totalChange != null ? (
          <Move label="Total gain" amount={signedPrice(portfolio.totalChange, "USD")} pct={portfolio.totalChangePct} digits={1} value={portfolio.totalChange} />
        ) : null}
      </div>
      <ul className="flex flex-col divide-y divide-foreground/6" aria-label="Positions by value">
        {rows.map(({ c, h }, i) => (
          <li key={c.q.symbol} className="grid grid-cols-[64px_minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1 py-2.5 text-sm sm:grid-cols-[64px_120px_110px_minmax(0,1fr)_72px]">
            <span className="font-mono font-semibold">{c.q.symbol}</span>
            <span className="text-muted-foreground tabular-nums max-sm:hidden">{h.shares != null ? sharesLabel(h.shares) : ""}</span>
            <span className="text-right font-medium tabular-nums sm:text-left">{formatPrice(h.value, c.q.currency)}</span>
            <span className="relative h-2 rounded-full bg-foreground/6 max-sm:col-span-2" aria-hidden="true">
              <span className="feed-grow-x absolute inset-y-0 left-0 rounded-full bg-primary/60" style={{ width: `${h.weightPct ?? 0}%`, "--i": i, transformOrigin: "left" } as CSSProperties} />
            </span>
            <span className={cn("text-right font-medium tabular-nums", moveClass(h.totalChangePct))}>
              {h.totalChangePct != null ? signedPct(h.totalChangePct) : ""}
            </span>
          </li>
        ))}
      </ul>
    </article>
  );
}

function Move({ label, amount, pct, digits, value }: { label: string; amount: string; pct: number | null; digits: number; value: number }) {
  return (
    <div>
      <div className="text-xs font-medium text-muted-foreground">{label}</div>
      <div className={cn("mt-1 text-lg font-semibold tabular-nums", moveClass(value))}>
        {amount}
        {pct != null ? <span className="ml-2">{signedPct(pct, digits)}</span> : null}
      </div>
    </div>
  );
}

// The holding in a line: "You · 40 shares · $9,916.00 · +39.1%" (the
// small cards leave the shares to the holdings card).
function HoldingLine({ h, currency, shares = true }: { h: Holding; currency: string | null; shares?: boolean }) {
  return (
    <p className="flex flex-wrap items-baseline gap-x-1.5 text-[13px] text-muted-foreground tabular-nums">
      <span>You</span>
      {shares && h.shares != null ? <span>· {sharesLabel(h.shares)}</span> : null}
      <span>· {formatPrice(h.value, currency)}</span>
      {h.totalChangePct != null ? <span className={cn("font-medium", moveClass(h.totalChangePct))}>· {signedPct(h.totalChangePct)}</span> : null}
    </p>
  );
}

// What the agent noticed: facts, each with its direction.
function Signals({ signals, max }: { signals: Signal[]; max: number }) {
  if (!signals.length) return null;
  return (
    <ul className="flex flex-col gap-1.5 text-[13px]" aria-label="Signals">
      {signals.slice(0, max).map((s) => {
        const Icon = s.tone === "up" ? ArrowUpRightIcon : s.tone === "down" ? ArrowDownRightIcon : EyeIcon;
        return (
          <li key={s.text} className="flex items-start gap-2">
            <Icon className={cn("mt-0.5 size-3.5 shrink-0", s.tone === "up" ? "text-success" : s.tone === "down" ? "text-destructive" : "text-warning")} aria-hidden="true" />
            <span>{s.text}</span>
          </li>
        );
      })}
    </ul>
  );
}

function HeroCard({ card: { q, t, history, insight }, timeZone, index }: { card: Card; timeZone: string; index: number }) {
  const points = downsample(history, HERO_POINTS);
  const range = rangeOf(history);
  const days = history.length > 1 ? Math.max(1, Math.round((history[history.length - 1].t - history[0].t) / DAY)) : 0;
  const r = rise(index);
  return (
    <article className={cn(CARD, "flex flex-col gap-5 p-6 sm:col-span-2 max-sm:p-5", r.className)} style={r.style}>
      <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-4">
        <div className="min-w-0">
          <div className="flex items-baseline gap-2.5">
            <span className="font-mono text-lg font-semibold">{q.symbol}</span>
            {q.name ? <span className="truncate text-muted-foreground">{q.name}</span> : null}
          </div>
          <div className="mt-2 font-heading text-[44px] leading-none font-semibold tracking-tight max-sm:text-[36px]">
            <AnimatedNumber value={q.price} format="price" currency={q.currency ?? undefined} />
          </div>
          <div className="mt-3 flex flex-wrap items-center gap-2 text-[13px] text-muted-foreground">
            <ChangeChip text={t.change} direction={t.direction} tone={chipTone(t.direction)} />
            <span>today</span>
            {t.swingPct ? <span>· usually ±{t.swingPct.toFixed(1)}% a day</span> : null}
          </div>
          {insight?.holding ? (
            <div className="mt-2">
              <HoldingLine h={insight.holding} currency={q.currency} />
            </div>
          ) : null}
        </div>
        {range && days > 0 && range.max > range.min ? <RangeMeter min={range.min} max={range.max} position={range.position} days={days} currency={q.currency} /> : null}
      </div>
      {points.length > 1 ? (
        <AreaChart
          points={points}
          format="price"
          currency={q.currency ?? undefined}
          height={200}
          label={`${q.symbol}, the last ${days} days`}
          timeZone={timeZone}
        />
      ) : (
        <p className="grid h-[120px] place-items-center rounded-2xl bg-muted/60 text-sm text-muted-foreground">The chart fills in as the agent pushes more quotes.</p>
      )}
      {insight?.signals.length ? <Signals signals={insight.signals} max={4} /> : null}
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 text-[13px] text-muted-foreground">
        <span className="min-w-0">{q.note ?? (q.agent_name ? <AgentLabel name={q.agent_name} color={q.agent_color} /> : null)}</span>
        <span>
          as of <Time iso={q.as_of} />
        </span>
      </div>
    </article>
  );
}

// Where the latest price sits between the window's low and high.
function RangeMeter({ min, max, position, days, currency }: { min: number; max: number; position: number; days: number; currency: string | null }) {
  const price = (n: number) => new Intl.NumberFormat("en-US", { maximumFractionDigits: 2, minimumFractionDigits: 2 }).format(n);
  const where = position >= 0.85 ? "Near the top" : position <= 0.15 ? "Near the bottom" : "Mid-range";
  return (
    <div className="flex w-full max-w-[260px] flex-col gap-2 text-[13px] sm:w-[240px]" aria-label={`${where} of its ${days}-day range, ${price(min)} to ${price(max)}${currency ? ` ${currency}` : ""}`}>
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-muted-foreground">{days}-day range</span>
        <span className="font-medium">{where}</span>
      </div>
      <div className="relative h-1.5 rounded-full bg-foreground/8" aria-hidden="true">
        <span className="absolute inset-y-0 left-0 rounded-full bg-primary/25" style={{ width: `${position * 100}%` }} />
        <span className="absolute top-1/2 size-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-primary ring-2 ring-card" style={{ left: `${position * 100}%` }} />
      </div>
      <div className="flex justify-between text-xs text-muted-foreground tabular-nums" aria-hidden="true">
        <span>{price(min)}</span>
        <span>{price(max)}</span>
      </div>
    </div>
  );
}

// The day at a glance: how many rose and fell, and the one that moved most
// against its usual day (lib/insights.ts's big-mover rule says when that's
// news). Worked out here, no model.
function MovesCard({ cards, index }: { cards: Card[]; index: number }) {
  const up = cards.filter((c) => c.t.direction === "up").length;
  const down = cards.filter((c) => c.t.direction === "down").length;
  const flat = cards.length - up - down;
  const moved = cards.filter((c) => c.t.changePct != null);
  const top = moved.sort((a, b) => Math.abs(b.t.changePct!) - Math.abs(a.t.changePct!))[0];
  const pct = top ? Math.abs(top.t.changePct!) : 0;
  const ratio = top?.t.swingPct ? pct / top.t.swingPct : null;
  const big = top ? pct >= BIG_MOVE_PCT || (ratio !== null && ratio >= SWING_RATIO && pct >= 1) : false;
  const r = rise(index);
  return (
    <article className={cn(CARD, "flex flex-col gap-5 p-6 max-sm:p-5", r.className)} style={r.style}>
      <div>
        <h3 className="text-sm font-medium text-muted-foreground">Today&apos;s moves</h3>
        <p className="mt-2 font-heading text-[26px] leading-tight font-semibold tracking-tight">
          {up} up<span className="text-muted-foreground"> · </span>
          {down} down
          {flat ? (
            <>
              <span className="text-muted-foreground"> · </span>
              {flat} flat
            </>
          ) : null}
        </p>
        {/* The split, as one bar. */}
        <div className="mt-3 flex h-2 gap-0.5 overflow-hidden rounded-full" aria-hidden="true">
          {up ? <span className="bg-success" style={{ flexGrow: up }} /> : null}
          {flat ? <span className="bg-foreground/15" style={{ flexGrow: flat }} /> : null}
          {down ? <span className="bg-destructive" style={{ flexGrow: down }} /> : null}
        </div>
      </div>
      <MoveBars cards={cards} />
      {top ? (
        <div className="flex flex-col gap-1.5 border-t border-foreground/8 pt-4">
          <span className="text-xs font-medium text-muted-foreground">{big ? "The big mover" : "Moved most"}</span>
          <div className="flex items-center gap-2">
            <span className="font-mono font-semibold">{top.q.symbol}</span>
            <ChangeChip text={top.t.change} direction={top.t.direction} tone={chipTone(top.t.direction)} />
          </div>
          <p className="text-[13px] text-muted-foreground">
            {ratio !== null ? `${ratio.toFixed(1)}× its usual day` : "No usual day to compare yet"}
            {top.q.note ? ` · ${top.q.note}` : ""}
          </p>
        </div>
      ) : null}
      {top ? <AskLink question={`Why did ${top.q.symbol} move ${top.t.change} today?`} label={`Ask about ${top.q.symbol}`} className="mt-auto self-start" /> : null}
    </article>
  );
}

// Each symbol's move today on one scale: a bar right of the middle for a
// rise, left for a fall, longest for the biggest.
function MoveBars({ cards }: { cards: Card[] }) {
  const rows = cards.filter((c) => c.t.changePct != null).sort((a, b) => b.t.changePct! - a.t.changePct!);
  const most = Math.max(...rows.map((c) => Math.abs(c.t.changePct!)), 0.01);
  if (rows.length < 2) return null;
  return (
    <ul className="flex flex-col gap-2" aria-label="Today's moves by symbol">
      {rows.map((c, i) => {
        const pct = c.t.changePct!;
        const width = `${(Math.abs(pct) / most) * 50}%`;
        return (
          <li key={c.q.symbol} className="grid grid-cols-[44px_minmax(0,1fr)_56px] items-center gap-2 text-xs">
            <span className="font-mono font-semibold">{c.q.symbol}</span>
            <span className="relative h-2 rounded-full bg-foreground/6" aria-hidden="true">
              <span className="absolute inset-y-[-2px] left-1/2 w-px bg-foreground/20" />
              <span
                className={cn("feed-grow-x absolute inset-y-0 rounded-full", pct >= 0 ? "left-1/2 bg-success" : "right-1/2 bg-destructive")}
                style={{ width, "--i": i, transformOrigin: pct >= 0 ? "left" : "right" } as CSSProperties}
              />
            </span>
            <span className={cn("text-right font-medium tabular-nums", pct > 0 ? "text-success" : pct < 0 ? "text-destructive" : "text-muted-foreground")}>{c.t.change}</span>
          </li>
        );
      })}
    </ul>
  );
}

function SymbolCard({ card: { q, t, insight }, index }: { card: Card; index: number }) {
  const r = rise(index);
  return (
    <article className={cn(CARD, "flex flex-col gap-3 p-5", r.className)} style={r.style}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="font-mono font-semibold">{q.symbol}</div>
          {q.name ? <div className="truncate text-[13px] text-muted-foreground">{q.name}</div> : null}
        </div>
        <ChangeChip text={t.change} direction={t.direction} tone={chipTone(t.direction)} />
      </div>
      <div className="font-heading text-[28px] leading-none font-semibold tracking-tight">
        <AnimatedNumber value={q.price} format="price" currency={q.currency ?? undefined} />
      </div>
      {insight?.holding ? <HoldingLine h={insight.holding} currency={q.currency} shares={false} /> : null}
      {t.points.length > 1 ? <Sparkline points={t.points} tone={tone(t.direction)} className="h-14" label={`${q.symbol}, the last 30 days`} /> : <div className="h-14" />}
      {insight?.signals.length ? <Signals signals={insight.signals} max={2} /> : null}
      {q.note ? <p className="line-clamp-2 text-[13px] text-muted-foreground">{q.note}</p> : null}
      <div className="mt-auto pt-1 text-xs text-muted-foreground">
        as of <Time iso={q.as_of} />
      </div>
    </article>
  );
}
