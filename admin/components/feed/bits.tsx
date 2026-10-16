import { cn } from "cn";
import { ArrowDownRightIcon, ArrowUpRightIcon, MinusIcon, SparklesIcon } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";

// Small pieces the feed layouts share. Server components, no client JS.

// The words above a tab's content: its name and a line about it.
export function FeedHeader({ title, description }: { title: string; description: ReactNode }) {
  return (
    <>
      <h2 className="font-heading text-lg leading-snug font-semibold tracking-tight">{title}</h2>
      <p className="mt-0.5 text-sm text-muted-foreground">{description}</p>
    </>
  );
}

// A change as a chip with an arrow. `tone` says whether it is good news:
// for a price that is the direction, for a latency it is the opposite (the
// caller decides, from goodDirection). Neutral when there is nothing to say.
export function ChangeChip({
  text,
  direction,
  tone,
  className,
}: {
  text: string;
  direction: "up" | "down" | "flat";
  tone: "good" | "bad" | "neutral";
  className?: string;
}) {
  if (!text || text === "—") return null;
  const Icon = direction === "up" ? ArrowUpRightIcon : direction === "down" ? ArrowDownRightIcon : MinusIcon;
  return (
    <span
      className={cn(
        "inline-flex h-6 shrink-0 items-center gap-1 rounded-full px-2 text-xs font-semibold whitespace-nowrap tabular-nums [&_svg]:size-3.5",
        tone === "good" && "bg-success/12 text-success dark:bg-success/15",
        tone === "bad" && "bg-destructive/10 text-destructive dark:bg-destructive/20",
        tone === "neutral" && "bg-secondary text-secondary-foreground",
        className,
      )}
    >
      <Icon aria-hidden="true" />
      {text}
    </span>
  );
}

// "Ask McFly" about something on the card: opens the assistant with the
// question already asked (/ask?q=). Only questions its snapshot can answer
// (the latest values, notes, projects, briefs and the Pulse; no history).
export function AskLink({ question, label = "Ask McFly", className }: { question: string; label?: string; className?: string }) {
  return (
    <Link
      href={`/ask?q=${encodeURIComponent(question)}`}
      className={cn(
        "relative z-10 inline-flex h-7 items-center gap-1.5 rounded-full px-2.5 text-xs font-medium text-muted-foreground no-underline ring-1 ring-foreground/10 transition-colors outline-none hover:bg-accent hover:text-accent-foreground hover:ring-transparent focus-visible:ring-2 focus-visible:ring-ring [&_svg]:size-3.5",
        className,
      )}
      title={question}
    >
      <SparklesIcon aria-hidden="true" />
      {label}
    </Link>
  );
}

// A quiet line under a grid: what isn't shown, and where to find it.
export function Footnote({ children }: { children: ReactNode }) {
  return <p className="mt-4 text-[13px] text-muted-foreground">{children}</p>;
}
