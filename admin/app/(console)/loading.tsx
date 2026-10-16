import { Skeleton } from "@/components/ui/skeleton";

// While a console page loads (they all read the database on every visit):
// the page's header and a few quiet card shapes, a wide one beside a narrow
// one over a full-width one, which is roughly how every page here is laid
// out, so the real page lands where the eye already is. It fades in only
// after 150 ms, so a quick page never flashes it. Feed pages have their own
// (feed/loading.tsx).
export default function ConsoleLoading() {
  return (
    <div aria-busy="true" aria-label="Loading" className="motion-safe:animate-in motion-safe:fade-in-0 motion-safe:delay-150 motion-safe:fill-mode-backwards motion-safe:duration-300">
      <div className="mb-6 flex flex-col gap-2.5">
        <Skeleton className="h-3 w-24 rounded-full motion-reduce:animate-none" />
        <Skeleton className="h-8 w-56 rounded-xl motion-reduce:animate-none" />
        <Skeleton className="h-4 w-80 max-w-full rounded-full motion-reduce:animate-none" />
      </div>
      <div className="flex flex-col gap-5">
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
          <Skeleton className="h-[300px] rounded-[24px] motion-reduce:animate-none" />
          <Skeleton className="h-[300px] rounded-[24px] max-lg:hidden motion-reduce:animate-none" />
        </div>
        <Skeleton className="h-[220px] rounded-[24px] motion-reduce:animate-none" />
      </div>
    </div>
  );
}
