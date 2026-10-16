import { Skeleton } from "@/components/ui/skeleton";

// While the feed or one of its pages loads: the header, a row where the
// tabs go, and a grid of card shapes, which is what every feed view and
// detail page is made of. Like the console's, it waits 150 ms to fade in.
export default function FeedLoading() {
  return (
    <div aria-busy="true" aria-label="Loading" className="motion-safe:animate-in motion-safe:fade-in-0 motion-safe:delay-150 motion-safe:fill-mode-backwards motion-safe:duration-300">
      <div className="mb-6 flex flex-col gap-2.5">
        <Skeleton className="h-8 w-40 rounded-xl motion-reduce:animate-none" />
        <Skeleton className="h-4 w-72 max-w-full rounded-full motion-reduce:animate-none" />
      </div>
      <Skeleton className="mb-5 h-9 w-[560px] max-w-full rounded-lg motion-reduce:animate-none" />
      <div className="mb-4 flex items-end justify-between gap-4">
        <div className="flex flex-col gap-2">
          <Skeleton className="h-5 w-28 rounded-lg motion-reduce:animate-none" />
          <Skeleton className="h-4 w-64 max-w-full rounded-full motion-reduce:animate-none" />
        </div>
        <Skeleton className="h-8 w-40 rounded-lg max-sm:hidden motion-reduce:animate-none" />
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Skeleton className="h-[380px] rounded-[24px] sm:col-span-2 motion-reduce:animate-none" />
        <Skeleton className="h-[380px] rounded-[24px] max-sm:hidden motion-reduce:animate-none" />
        {Array.from({ length: 3 }, (_, i) => (
          <Skeleton key={i} className="h-[240px] rounded-[24px] motion-reduce:animate-none" />
        ))}
      </div>
    </div>
  );
}
