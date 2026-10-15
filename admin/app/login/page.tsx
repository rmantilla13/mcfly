import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/Brand";
import { LoginForm } from "@/components/LoginForm";
import { DemoBanner } from "@/components/Shell";
import { readString } from "@/components/bits";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { NOT_ADMIN, isDemo } from "@/lib/data";
import { safeNextPath } from "@/lib/paths";
import { signInAction } from "./actions";

export const metadata: Metadata = { title: "Sign in" };

type Props = { searchParams: Promise<Record<string, string | string[] | undefined>> };

const ERRORS: Record<string, string> = {
  not_admin: `${NOT_ADMIN} Sign in with that account, or ask it to add you (admin_set_admin).`,
  config: "Supabase isn't configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY and restart (see admin/README.md).",
};

export default async function LoginPage({ searchParams }: Props) {
  const sp = await searchParams;
  const demo = await isDemo();
  const code = readString(sp.error);
  const error = Object.hasOwn(ERRORS, code) ? ERRORS[code] : undefined; // not ?error=__proto__
  const next = safeNextPath(readString(sp.next));

  return (
    <>
      {demo ? <DemoBanner /> : null}
      <main className="relative grid min-h-screen place-items-center gap-5 overflow-hidden px-4 py-12">
        {/* The display's glow, softened into the canvas. */}
        <div
          className="pointer-events-none absolute top-1/2 left-1/2 size-[980px] -translate-x-1/2 -translate-y-[46%] rounded-full opacity-25 blur-[90px]"
          style={{
            background:
              "conic-gradient(from 200deg, transparent 0deg, var(--glow-1) 40deg, var(--glow-2) 100deg, var(--glow-3) 150deg, transparent 200deg, transparent 360deg)",
          }}
          aria-hidden="true"
        />
        <Card className="relative w-full max-w-[420px] shadow-2xl shadow-foreground/10">
          <CardHeader className="gap-1">
            <div className="mb-4 flex items-center gap-3">
              <BrandMark className="size-11 rounded-2xl" />
              <span className="text-lg font-bold tracking-tight">
                McFly <span className="ml-1 font-semibold text-muted-foreground">Console</span>
              </span>
            </div>
            <CardTitle className="text-2xl font-semibold tracking-tight">Sign in</CardTitle>
            <CardDescription>For McFly&apos;s admin only.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            {sp.signed_out ? (
              <Alert>
                <AlertTitle>You&apos;re signed out.</AlertTitle>
              </Alert>
            ) : null}
            {error ? (
              <Alert variant="destructive">
                <AlertTitle>Can&apos;t sign in</AlertTitle>
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            ) : null}
            {demo ? (
              <>
                <Alert>
                  <AlertTitle>Demo mode is on, so there&apos;s no sign-in.</AlertTitle>
                  <AlertDescription>Everything in the console is fixture data.</AlertDescription>
                </Alert>
                <Button size="lg" asChild>
                  <Link href={next}>Open the demo console</Link>
                </Button>
              </>
            ) : (
              <LoginForm action={signInAction} next={next} />
            )}
          </CardContent>
        </Card>
        <p className="relative text-center text-[13px] text-muted-foreground">
          Access is limited to accounts listed in platform_admins.
        </p>
      </main>
    </>
  );
}
