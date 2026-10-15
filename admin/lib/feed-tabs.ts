// The feed page's tabs, as ?tab= names them. Plain so the server page and
// the client Tabs can both read it.
export const FEED_TABS = ["briefs", "markets", "news", "projects", "metrics", "dashboards", "calendar"] as const;
export type FeedTab = (typeof FEED_TABS)[number];

export function readFeedTab(value: string | string[] | undefined): FeedTab {
  const v = Array.isArray(value) ? value[0] : value;
  return (FEED_TABS as readonly string[]).includes(v ?? "") ? (v as FeedTab) : "briefs";
}
