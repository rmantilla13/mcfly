import { cn } from "cn";
import { cookies } from "next/headers";
import type { ReactNode } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { TODAY_LAYOUT_COOKIE, todayLayout } from "@/lib/today-layout";

// Today while it loads: the page's grid (components/today/TodayView.tsx)
// with the usual tiles in their places, so nothing jumps when it arrives.

function Tile({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cn("flex min-w-0 flex-col gap-4 rounded-[26px] bg-card p-5 ring-1 ring-foreground/[0.06]", className)}>{children}</div>;
}

// On a card, the skeleton's own muted fill barely shows; a touch of the ink does.
const FILL = "bg-foreground/[0.06] motion-reduce:animate-none";

function Bone({ className }: { className?: string }) {
  return <Skeleton className={cn("rounded-full", FILL, className)} />;
}

function Block({ className }: { className?: string }) {
  return <Skeleton className={cn(FILL, className)} />;
}

function Head() {
  return <Bone className="h-3 w-28" />;
}

export default async function TodayLoading() {
  // Bento and Assistant arrange the page differently: a plain block stands in
  // for them, rather than Today's grid jumping into another.
  if (todayLayout((await cookies()).get(TODAY_LAYOUT_COOKIE)?.value) !== "today") {
    return (
      <div className="flex flex-col gap-4">
        <div className="flex justify-end">
          <Bone className="h-11 w-72 sm:h-9" />
        </div>
        <Block className="h-[560px] rounded-[26px]" />
      </div>
    );
  }
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-6 xl:grid-cols-12" role="status">
      <span className="sr-only">Loading Today…</span>
      <Tile className="justify-between p-6 lg:col-span-3 xl:col-span-5">
        <Bone className="h-4 w-40" />
        <div className="flex flex-col gap-3">
          <Bone className="h-[76px] w-64 rounded-2xl max-md:h-14" />
          <Bone className="h-3.5 w-44" />
        </div>
      </Tile>
      <Tile className="min-h-[184px] justify-between p-6 lg:col-span-3 xl:col-span-7">
        <Bone className="h-3 w-36" />
        <div className="flex items-end justify-between gap-5">
          <div className="flex flex-col gap-2.5">
            <Bone className="h-7 w-56" />
            <Bone className="h-3.5 w-40" />
          </div>
          <Block className="size-[100px] shrink-0 rounded-full" />
        </div>
      </Tile>

      <Tile className="lg:col-span-6 xl:col-span-7">
        <Head />
        <Block className="h-[72px] rounded-[20px]" />
        <div className="grid gap-2.5 sm:grid-cols-2">
          {[0, 1, 2, 3].map((k) => (
            <Block key={k} className="h-[68px] rounded-[20px]" />
          ))}
        </div>
      </Tile>
      <Tile className="lg:col-span-6 xl:col-span-5">
        <Head />
        <Block className="h-[112px] rounded-[20px]" />
        <div className="flex flex-wrap gap-2">
          {["w-40", "w-32", "w-44"].map((w) => (
            <Bone key={w} className={cn("h-9", w)} />
          ))}
        </div>
        <Block className="mt-auto h-[68px] rounded-[28px]" />
      </Tile>

      <Tile className="lg:col-span-6 xl:col-span-8">
        <Head />
        <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-4">
          {[0, 1, 2, 3].map((k) => (
            <Block key={k} className="h-[150px] rounded-[20px]" />
          ))}
        </div>
      </Tile>
      <Tile className="lg:col-span-6 xl:col-span-4">
        <Head />
        {[0, 1, 2, 3].map((k) => (
          <div key={k} className="flex items-center gap-3">
            <div className="flex flex-1 flex-col gap-2">
              <Bone className="h-3 w-24" />
              <Bone className="h-4 w-20" />
            </div>
            <Bone className="h-6 w-16" />
          </div>
        ))}
      </Tile>

      <Tile className="lg:col-span-6 xl:col-span-7 xl:row-span-2">
        <Head />
        {[0, 1, 2, 3, 4].map((k) => (
          <div key={k} className="grid grid-cols-[3.5rem_1.5rem_minmax(0,1fr)] items-start gap-x-2">
            <Bone className="mt-3 ml-auto h-3.5 w-10" />
            <Block className="mx-auto mt-4 size-2.5 rounded-full" />
            <Block className="h-[72px] rounded-[20px]" />
          </div>
        ))}
      </Tile>
      <Tile className="p-6 lg:col-span-3 xl:col-span-5">
        <Bone className="h-5 w-48" />
        <Bone className="mt-6 h-6 w-56" />
        <Bone className="h-3.5 w-full" />
        <Bone className="h-3.5 w-4/5" />
        <Bone className="h-3.5 w-3/5" />
      </Tile>
      <Tile className="gap-0 overflow-hidden p-0 lg:col-span-3 xl:col-span-5">
        <Block className="h-36 rounded-none" />
        <div className="flex flex-col gap-3 p-5">
          <Bone className="h-3 w-32" />
          <Bone className="h-5 w-full" />
          <Bone className="h-3.5 w-4/5" />
        </div>
      </Tile>
    </div>
  );
}
