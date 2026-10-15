import { LogOutIcon } from "lucide-react";
import type { ReactNode } from "react";
import { signOutAction } from "@/app/(console)/actions";
import { Brand } from "@/components/Brand";
import { NavLinks } from "@/components/NavLinks";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

export function DemoBanner() {
  return (
    <div
      className="flex items-center gap-3 border-b border-warning/20 bg-warning/10 px-6 py-2.5 text-sm text-warning max-md:px-4"
      role="note"
    >
      <Badge variant="warning">Demo data</Badge>
      <span>
        <strong className="font-semibold">Sign-in is off and nothing here is real.</strong> Fixture data from
        NEXT_PUBLIC_ADMIN_DEMO=1; changes reset when the server restarts.
      </span>
    </div>
  );
}

export function Shell({ email, demo, children }: { email: string; demo: boolean; children: ReactNode }) {
  return (
    <div className="grid min-h-screen grid-cols-[248px_minmax(0,1fr)] max-md:grid-cols-1">
      <aside className="border-r border-sidebar-border bg-sidebar text-sidebar-foreground max-md:border-r-0 max-md:border-b">
        <div className="sticky top-0 flex h-screen flex-col gap-6 px-4 py-5 max-md:static max-md:h-auto max-md:flex-row max-md:flex-wrap max-md:items-center max-md:gap-x-4 max-md:gap-y-3 max-md:py-3">
          <Brand />
          <div className="max-md:order-3 max-md:w-full">
            <NavLinks />
          </div>
          <div className="mt-auto grid gap-2 rounded-2xl bg-sidebar-accent/60 p-3.5 max-md:ml-auto max-md:mt-0 max-md:bg-transparent max-md:p-0">
            <span className="text-xs text-muted-foreground max-md:hidden">Signed in as</span>
            <span className="truncate text-sm font-semibold max-md:hidden" title={email}>
              {email}
            </span>
            <form action={signOutAction}>
              <Button type="submit" variant="ghost" size="sm" className="-ml-2">
                <LogOutIcon data-icon="inline-start" />
                Sign out
              </Button>
            </form>
          </div>
        </div>
      </aside>
      <div className="flex min-w-0 flex-col">
        {demo ? <DemoBanner /> : null}
        <main className="w-full max-w-[1240px] px-10 pt-9 pb-16 max-md:px-4 max-md:pt-6 max-md:pb-12">{children}</main>
      </div>
    </div>
  );
}
