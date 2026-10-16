// Which layout the web's Today page shows: today (the page as it was), bento
// (tiles, as the display's Bento) or assistant (McFly's summary first, as the
// display's Assistant). Picked with the switcher at the top of the page and
// remembered by this browser in a cookie, so the server renders the right
// one from the first byte. It is this browser's choice: the displays keep
// their own (devices.settings.homeLayout).
export const TODAY_LAYOUTS = ["today", "bento", "assistant"] as const;
export type TodayLayout = (typeof TODAY_LAYOUTS)[number];
export const TODAY_LAYOUT_COOKIE = "mcfly_today_layout";

// A cookie value as a layout: anything this build doesn't know is today.
export function todayLayout(value: string | null | undefined): TodayLayout {
  return (TODAY_LAYOUTS as readonly string[]).includes(value ?? "") ? (value as TodayLayout) : "today";
}
