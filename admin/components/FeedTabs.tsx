"use client";

import { useState, type ReactNode } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { readFeedTab, type FeedTab } from "@/lib/feed-tabs";

export type FeedTabSpec = { value: FeedTab; label: string; count: number; content: ReactNode };

// The feeds as tabs. The chosen tab is kept in ?tab= (without a navigation,
// so a reload or a pagination link lands on the same one); the content of
// every tab is rendered on the server.
export function FeedTabs({ initial, tabs }: { initial: FeedTab; tabs: FeedTabSpec[] }) {
  const [tab, setTab] = useState<FeedTab>(initial);
  const change = (next: string) => {
    const t = readFeedTab(next);
    setTab(t);
    const url = new URL(window.location.href);
    url.searchParams.set("tab", t);
    url.searchParams.delete("page");
    url.searchParams.delete("deleted");
    window.history.replaceState(window.history.state, "", url);
  };
  return (
    <Tabs value={tab} onValueChange={change}>
      <TabsList className="h-auto max-w-full flex-wrap justify-start">
        {tabs.map((t) => (
          <TabsTrigger key={t.value} value={t.value} className="h-7 flex-none">
            {t.label} <TabCount n={t.count} />
          </TabsTrigger>
        ))}
      </TabsList>
      {tabs.map((t) => (
        <TabsContent key={t.value} value={t.value}>
          {t.content}
        </TabsContent>
      ))}
    </Tabs>
  );
}

function TabCount({ n }: { n: number }) {
  return <span className="rounded-full bg-foreground/8 px-1.5 text-xs tabular-nums text-muted-foreground">{n}</span>;
}
