import { Fragment, type ReactNode } from "react";
import { cn } from "cn";
import { parseMarkdown, type Align, type Block, type Inline, type Tone } from "@/lib/markdown";

// An answer from the full-screen Ask, set for reading: lib/markdown.ts parses
// it, this turns the parts into elements. Text only ever lands as text.
//
// The assistant's own shapes (its `layout` skill, docs/ASSISTANT.md) draw as
// the phone draws them: a tagged item's tag is a chip, a stats block is a
// row of tiles, and a table narrower than the page is a grid while a wider
// one stacks each row into a card with the header's words as labels.

// The colour a tone or a tag's word carries: what's late or down in red,
// what's done or up in green, what's waiting in amber, a day in the accent.
function toneClass(tone: Tone | string | undefined): string {
  const word = (tone ?? "").toLowerCase();
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
        "mr-2 inline-flex shrink-0 items-center rounded-full px-2 py-0.5 align-[0.1em] text-[0.72em] font-semibold tracking-wide whitespace-nowrap",
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

const alignClass = (a: Align) => (a === "right" ? "text-right" : a === "center" ? "text-center" : "text-left");

function block(b: Block, key: number, depth = 0): ReactNode {
  switch (b.t) {
    case "heading":
      return b.level <= 2 ? (
        <h2 key={key} className="mt-9 mb-3 text-[1.45em] leading-tight font-semibold tracking-[-0.015em] text-foreground first:mt-0">
          {inline(b.c)}
        </h2>
      ) : (
        <h3 key={key} className="mt-8 mb-2.5 text-[1.12em] leading-snug font-semibold tracking-[-0.01em] text-foreground first:mt-0">
          {inline(b.c)}
        </h3>
      );
    case "p":
      return (
        <p key={key} className="my-4 first:mt-0 last:mb-0">
          {inline(b.c)}
        </p>
      );
    case "list": {
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
            <li key={i} className={cn("pl-1.5", item.tag && "list-none -ml-6")}>
              {item.tag ? <Chip tag={item.tag} /> : null}
              {inline(item.c)}
              {item.sub ? block(item.sub, 0, depth + 1) : null}
            </li>
          ))}
        </Tag>
      );
    }
    case "table": {
      // Narrow (three short columns at most): a grid as wide as the page,
      // and on a phone too. Wider, or with a sentence in a cell: each row is
      // a card, the first cell its title and the others label: value lines,
      // so nothing is squeezed, cut off or drawn over its neighbour. On a
      // phone every table is cards. Class names are written out whole, so
      // Tailwind's scanner finds them.
      const longest = Math.max(0, ...b.rows.flat().map((cell) => inlineLength(cell)));
      const stack = b.head.length > 3 || longest > 24;
      const c = stack ? STACKED : STACKED_ON_PHONE;
      return (
        <div key={key} className="my-5 overflow-hidden rounded-xl border first:mt-0 last:mb-0">
          <table className={cn("w-full border-collapse text-[0.92em] tabular-nums", c.table)}>
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
                      {i > 0 && inlineLength(cell) > 0 ? <span className={cn("hidden text-muted-foreground", c.label)}>{inline(b.head[i])}: </span> : null}
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
        <div key={key} className="my-5 grid grid-cols-2 gap-2 first:mt-0 last:mb-0 sm:grid-cols-3">
          {b.items.map((s, i) => (
            <div key={i} className="rounded-xl border bg-card px-4 py-3">
              <div className="truncate text-xs font-medium tracking-wide text-muted-foreground uppercase">{s.label}</div>
              <div className={cn("mt-1 text-[1.5em] leading-tight font-semibold tracking-tight tabular-nums", toneClass(s.tone) || "text-foreground")}>
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

// A table as cards, always or below the sm breakpoint (a phone).
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

export function Markdown({ text, className }: { text: string; className?: string }) {
  return <div className={className}>{parseMarkdown(text).map((b, i) => block(b, i))}</div>;
}
