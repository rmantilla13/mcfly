import { Fragment, type ReactNode } from "react";
import { cn } from "cn";
import { parseMarkdown, type Align, type Block, type Inline } from "@/lib/markdown";

// An answer from the full-screen Ask, set for reading: lib/markdown.ts parses
// it, this turns the parts into elements. Text only ever lands as text.

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
            <li key={i} className="pl-1.5">
              {inline(item.c)}
              {item.sub ? block(item.sub, 0, depth + 1) : null}
            </li>
          ))}
        </Tag>
      );
    }
    case "table":
      return (
        // As wide as its words want, up to a point a column wraps at; wider
        // than the page (a phone), it scrolls sideways rather than squeezing.
        <div key={key} className="my-5 overflow-x-auto rounded-xl border first:mt-0 last:mb-0">
          <table className="w-max min-w-full border-collapse text-[0.92em] tabular-nums">
            <thead className="bg-muted/60">
              <tr>
                {b.head.map((cell, i) => (
                  <th key={i} scope="col" className={cn("px-4 py-2.5 font-semibold whitespace-nowrap text-foreground", alignClass(b.align[i]))}>
                    {inline(cell)}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {b.rows.map((row, r) => (
                <tr key={r} className="border-t">
                  {row.map((cell, i) => (
                    <td key={i} className={cn("max-w-[22rem] px-4 py-2.5 align-top", alignClass(b.align[i]), i === 0 && "font-medium text-foreground")}>
                      {inline(cell)}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
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

export function Markdown({ text, className }: { text: string; className?: string }) {
  return <div className={className}>{parseMarkdown(text).map((b, i) => block(b, i))}</div>;
}
