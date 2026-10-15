import type { Metadata } from "next";
import Link from "next/link";
import { BrandMark } from "@/components/Brand";
import { LoginForm } from "@/components/LoginForm";
import { LoginScene } from "@/components/login/LoginScene";
import { DemoBanner } from "@/components/Shell";
import { readString } from "@/components/bits";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { NOT_ADMIN, isDemo } from "@/lib/data";
import { safeNextPath } from "@/lib/paths";
import { signInAction } from "./actions";

export const metadata: Metadata = { title: "Sign in" };

type Props = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const ERRORS: Record<string, string> = {
  not_admin: `${NOT_ADMIN} Sign in with that account, or ask it to add you (admin_set_admin).`,
  config:
    "Supabase isn't configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY and restart (see admin/README.md).",
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
      <main>
        <LoginScene>
          <Card className="relative w-full border-0 bg-transparent shadow-none ring-0">
            <CardHeader className="gap-1">
              <div className="mb-4 flex items-center gap-3">
                <span className="relative">
                  <span
                    className="absolute inset-0 animate-ping rounded-2xl bg-glow-2/30 [animation-duration:2.8s] motion-reduce:animate-none"
                    aria-hidden="true"
                  />
                  <BrandMark className="relative size-11 rounded-2xl" />
                </span>
                <span className="text-lg font-bold tracking-tight">
                  McFly{" "}
                  <span className="ml-1 font-semibold text-muted-foreground">
                    Console
                  </span>
                </span>
              </div>
              <CardTitle className="text-2xl font-semibold tracking-tight">
                Sign in
              </CardTitle>
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
                    <AlertTitle>
                      Demo mode is on, so there&apos;s no sign-in.
                    </AlertTitle>
                    <AlertDescription>
                      Everything in the console is fixture data.
                    </AlertDescription>
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
        </LoginScene>
      </main>
    </>
  );
}
