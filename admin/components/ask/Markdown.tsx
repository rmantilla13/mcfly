import { Fragment, type ReactNode } from "react";
import { cn } from "cn";
import { parseMarkdown, splitLead, type Align, type Block, type Inline, type ListItem, type Tone } from "@/lib/markdown";

// An answer from the full-screen Ask, set for reading: lib/markdown.ts parses
// it, this turns the parts into elements. Text only ever lands as text.
//
// The assistant's own shapes (its `layout` skill, docs/ASSISTANT.md) draw as
// the phone draws them (AnswerMarkdown in Components.swift): ### headings
// are small spaced capitals with a hairline, the answer's first line is a
// size up, a list with tags is a card of rows (the name, its chip at the
// row's end, the detail under them), a bold name opening any item gets a
// line of its own, a stats block is a row of tiles, and a table narrower
// than the page is a grid while a wider one stacks each row into a card.

// The colour a tone or a tag's first word carries: what's late or down in
// red, what's done or up in green, what's waiting in amber, a day in the
// accent. "Waiting on Sophie" is amber like "Waiting".
function toneClass(tone: Tone | string | undefined): string {
  const word = (tone ?? "").toLowerCase().split(/[^a-z]+/).find(Boolean) ?? "";
  if (/^(down|overdue|late|blocked|missed|off)$/.test(word)) return "text-red-600 dark:text-red-400";
  if (/^(up|done|paid|sent|shipped|on)$/.test(word)) return "text-emerald-700 dark:text-emerald-400";
  if (/^(watch|waiting|pending|soon|risk)$/.test(word)) return "text-amber-700 dark:text-amber-400";
  return "";
}

function Chip({ tag }: { tag: string }) {
  const tone = toneClass(tag);
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[0.72em] font-semibold tracking-wide whitespace-nowrap",
        tone ? cn("bg-current/10", tone) : "bg-primary/10 text-primary",
      )}
    >
      {tag}
    </span>
  );
}

function inline(nodes: Inline[]): ReactNode {
  return nodes.map((n, i) => {
    switch (n.t) {
      case "text":
        return <Fragment key={i}>{n.v}</Fragment>;
      case "br":
        return <br key={i} />;
      case "code":
        return (
          <code key={i} className="rounded-md bg-muted px-1.5 py-0.5 font-mono text-[0.88em]">
            {n.v}
          </code>
        );
      case "strong":
        return (
          <strong key={i} className="font-semibold text-foreground">
            {inline(n.c)}
          </strong>
        );
      case "em":
        return <em key={i}>{inline(n.c)}</em>;
      case "del":
        return (
          <del key={i} className="text-muted-foreground">
            {inline(n.c)}
          </del>
        );
    }
  });
}

// An item's words: a bold name opening it on a line of its own, the rest
// under it a little quieter and starting with a capital; anything else as is.
function ItemText({ c }: { c: Inline[] }) {
  const { lead, detail } = splitLead(c);
  if (!detail) return <>{inline(c)}</>;
  return (
    <>
      <span className="block font-semibold text-foreground">{inline(lead)}</span>
      <span className="mt-0.5 block text-[0.94em] text-foreground/80 first-letter:uppercase">{inline(detail)}</span>
    </>
  );
}

// A list whose items carry tags: one card, a row an item. The name leads,
// the chip sits at the row's end (so the names line up), the detail runs
// the card's width under them.
function Items({ b }: { b: Extract<Block, { t: "list" }> }) {
  const row = (item: ListItem, i: number) => {
    const { lead, detail } = splitLead(item.c);
    return (
      <li key={i} className="px-4 py-3">
        <div className="flex items-baseline gap-3">
          {b.ordered ? <span className="font-semibold text-muted-foreground tabular-nums">{b.start + i}.</span> : null}
          <span className={cn("min-w-0 flex-1", detail && "font-semibold text-foreground")}>{inline(lead)}</span>
          {item.tag ? <Chip tag={item.tag} /> : null}
        </div>
        {detail ? <div className="mt-1 text-[0.94em] text-foreground/80 first-letter:uppercase">{inline(detail)}</div> : null}
        {item.sub ? block(item.sub, 0, 1) : null}
      </li>
    );
  };
  return <ul className="my-5 divide-y overflow-hidden rounded-xl border bg-card first:mt-0 last:mb-0">{b.items.map(row)}</ul>;
}

const alignClass = (a: Align) => (a === "right" ? "text-right" : a === "center" ? "text-center" : "text-left");

function block(b: Block, key: number, depth = 0): ReactNode {
  switch (b.t) {
    case "heading":
      return b.level <= 2 ? (
        <h2 key={key} className="mt-9 mb-3 text-[1.45em] leading-tight font-semibold tracking-[-0.015em] text-foreground first:mt-0">
          {inline(b.c)}
        </h2>
      ) : (
        // A section's name in small spaced capitals with a hairline after it.
        <h3 key={key} className="mt-8 mb-3 flex items-center gap-3 text-[0.78em] font-bold tracking-[0.12em] text-muted-foreground uppercase first:mt-0">
          <span className="shrink-0">{inline(b.c)}</span>
          <span aria-hidden className="h-px min-w-4 flex-1 bg-border" />
        </h3>
      );
    case "p":
      // The answer itself comes first: a size up, so it's read before the detail.
      return (
        <p key={key} className="my-4 first:mt-0 first:text-[1.12em] first:leading-snug last:mb-0">
          {inline(b.c)}
        </p>
      );
    case "list": {
      if (depth === 0 && b.items.some((item) => item.tag)) return <Items key={key} b={b} />;
      const Tag = b.ordered ? "ol" : "ul";
      return (
        <Tag
          key={key}
          start={b.ordered && b.start !== 1 ? b.start : undefined}
          className={cn(
            "flex flex-col gap-2 pl-6",
            b.ordered ? "list-decimal marker:font-medium marker:text-muted-foreground" : depth ? "list-[circle] marker:text-muted-foreground" : "list-disc marker:text-muted-foreground",
            depth ? "mt-2" : "my-4 first:mt-0 last:mb-0",
          )}
        >
          {b.items.map((item, i) => (
            <li key={i} className="pl-1.5">
              <ItemText c={item.c} />
              {item.sub ? block(item.sub, 0, depth + 1) : null}
            </li>
          ))}
        </Tag>
      );
    }
    case "table": {
      // Narrow (three short columns at most): a grid as wide as the page.
      // Wider, or with a sentence in a cell: each row is a card, the first
      // cell its title and the others label: value lines (just the value
      // with two columns), so nothing is squeezed, cut off or drawn over its
      // neighbour. On a phone only a few short figures stay a grid. Class
      // names are written out whole, so Tailwind's scanner finds them.
      const longest = Math.max(0, ...b.rows.flat().map((cell) => inlineLength(cell)));
      const widest = Math.max(0, ...[b.head, ...b.rows].map((row) => row.reduce((n, cell) => n + inlineLength(cell), 0)));
      const stack = b.head.length > 3 || longest > 24;
      // A few short figures (symbol, price, change) fit a phone as a grid, as on the iPhone.
      const c = stack ? STACKED : widest > 34 ? STACKED_ON_PHONE : GRID;
      return (
        <div key={key} className="my-5 overflow-x-auto rounded-xl border first:mt-0 last:mb-0">
          <table className={cn("w-full border-collapse text-[0.92em] tabular-nums", c.table, c === GRID && "[overflow-wrap:normal]")}>
            <thead className={cn("bg-muted/60", c.head)}>
              <tr>
                {b.head.map((cell, i) => (
                  <th key={i} scope="col" className={cn("px-4 py-2.5 font-semibold whitespace-nowrap text-foreground", alignClass(b.align[i]))}>
                    {inline(cell)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className={c.body}>
              {b.rows.map((row, r) => (
                <tr key={r} className={cn("border-t first:border-t-0", c.row)}>
                  {row.map((cell, i) => (
                    <td
                      key={i}
                      className={cn(
                        "px-4 py-2.5 align-top",
                        alignClass(b.align[i]),
                        i === 0 ? cn("font-medium text-foreground", c.title) : cn("text-foreground/90", c.cell),
                      )}
                    >
                      {/* Two columns read as a name and what it says: the label would only repeat the header. */}
                      {i > 0 && b.head.length > 2 && inlineLength(cell) > 0 ? (
                        <span className={cn("hidden text-muted-foreground", c.label)}>{inline(b.head[i])}: </span>
                      ) : null}
                      {inline(cell)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
    }
    case "stats":
      return (
        <div key={key} className="my-5 grid grid-cols-2 gap-2 first:mt-0 last:mb-0 sm:grid-cols-[repeat(auto-fit,minmax(9.5rem,1fr))]">
          {b.items.map((s, i) => (
            <div key={i} className="@container rounded-xl border bg-card px-4 py-3">
              <div className="truncate text-xs font-medium tracking-wide text-muted-foreground uppercase">{s.label}</div>
              {/* A figure never breaks: one line, a short one large, a long one sized to its tile, cut with … only past twelve or so characters. */}
              <div
                className={cn(
                  "mt-1 truncate leading-tight font-semibold tracking-tight whitespace-nowrap tabular-nums [overflow-wrap:normal]",
                  s.value.length <= 7 ? "text-[1.6em]" : "text-[min(1.5em,13cqi)]",
                  toneClass(s.tone) || "text-foreground",
                )}
              >
                {s.value}
              </div>
            </div>
          ))}
        </div>
      );
    case "quote":
      return (
        <blockquote key={key} className="my-4 border-l-[3px] border-primary/50 pl-4 text-muted-foreground first:mt-0 last:mb-0">
          {inline(b.c)}
        </blockquote>
      );
    case "code":
      return (
        <pre key={key} className="my-4 overflow-x-auto rounded-xl bg-muted px-4 py-3 font-mono text-[0.85em] leading-relaxed first:mt-0 last:mb-0">
          {b.v}
        </pre>
      );
    case "hr":
      return <hr key={key} className="my-7 border-border" />;
  }
}

// A table as a grid everywhere, as cards everywhere, or as cards below the
// sm breakpoint (a phone).
const GRID = { table: "", head: "", body: "", row: "", title: "", cell: "", label: "" };
const STACKED = {
  table: "block",
  head: "sr-only",
  body: "block",
  row: "block px-4 py-3",
  title: "block p-0 text-left mb-1.5 font-semibold",
  cell: "block p-0 text-left mt-1",
  label: "inline",
};
const STACKED_ON_PHONE = {
  table: "max-sm:block",
  head: "max-sm:sr-only",
  body: "max-sm:block",
  row: "max-sm:block max-sm:px-4 max-sm:py-3",
  title: "max-sm:block max-sm:p-0 max-sm:text-left max-sm:mb-1.5 max-sm:font-semibold",
  cell: "max-sm:block max-sm:p-0 max-sm:text-left max-sm:mt-1",
  label: "max-sm:inline",
};

// How many characters a cell's words come to, for the choice of grid or cards.
function inlineLength(nodes: Inline[]): number {
  return nodes.reduce((n, node) => n + (node.t === "text" || node.t === "code" ? node.v.length : node.t === "br" ? 1 : inlineLength(node.c)), 0);
}

// A word too long for the line (a link, a path, a file name) breaks where it
// has to rather than pushing the page wider than a phone.
export function Markdown({ text, className }: { text: string; className?: string }) {
  return <div className={cn("min-w-0 [overflow-wrap:anywhere]", className)}>{parseMarkdown(text).map((b, i) => block(b, i))}</div>;
}
