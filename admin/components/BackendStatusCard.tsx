import { CheckCircle2Icon, CircleAlertIcon, ExternalLinkIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Time } from "@/components/bits";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { BackendStatus } from "@/lib/types";

// Settings → Backend: whether McFly's Supabase project is fully set up. Every
// row says what's wrong and where to fix it. Secrets show as set or missing,
// never their values.

function Row({ ok, title, children }: { ok: boolean | null; title: string; children: ReactNode }) {
  return (
    <li className="flex items-start gap-3 py-2.5">
      {ok === false ? (
        <CircleAlertIcon className="mt-0.5 size-4 shrink-0 text-warning" />
      ) : (
        <CheckCircle2Icon className={ok ? "mt-0.5 size-4 shrink-0 text-success" : "mt-0.5 size-4 shrink-0 text-muted-foreground"} />
      )}
      <div className="min-w-0">
        <div className="text-sm font-medium">{title}</div>
        <div className="text-[13px] text-muted-foreground">{children}</div>
      </div>
    </li>
  );
}

export function BackendStatusCard({ status }: { status: BackendStatus }) {
  // "; open in Supabase" with a link to the right page, or just a full stop.
  const dash = (path: string) =>
    status.projectRef ? (
      <>
        ;{" "}
        <a href={`https://supabase.com/dashboard/project/${status.projectRef}/${path}`} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1">
          open in Supabase <ExternalLinkIcon className="size-3" />
        </a>
      </>
    ) : (
      "."
    );
  const missingFns = status.functions.filter((f) => !f.ok).map((f) => f.name);
  const secret = (name: string) => status.secrets?.[name] === true;
  const migrated = status.latestMigration != null && status.latestMigration >= status.expectedMigration;
  const jobs = status.cron ?? [];
  const scheduled = jobs.length >= 2 && jobs.every((j) => j.active) && status.vault?.project_url && status.vault?.cron_secret;

  return (
    <Card className="max-w-3xl">
      <CardHeader>
        <CardTitle>Backend</CardTitle>
        <CardDescription>McFly&apos;s Supabase project: what&apos;s deployed and what still needs a key.</CardDescription>
      </CardHeader>
      <CardContent>
        <ul className="divide-y">
          <Row ok={migrated} title="Database">
            {migrated ? `Up to date (migration ${status.latestMigration}).` : `Needs migrations: has ${status.latestMigration ?? "none"}, this console expects ${status.expectedMigration}. Run supabase db push.`}
          </Row>
          <Row ok={missingFns.length === 0} title="Functions">
            {missingFns.length === 0 ? `All ${status.functions.length} answer.` : `Not answering: ${missingFns.join(", ")}. Run supabase functions deploy.`}
          </Row>
          <Row ok={status.secrets ? secret("ANTHROPIC_API_KEY") : null} title="Claude (assistant)">
            {status.secrets == null ? "Couldn't check." : secret("ANTHROPIC_API_KEY") ? "ANTHROPIC_API_KEY is set." : <>Add ANTHROPIC_API_KEY under Edge Functions → Secrets{dash("functions/secrets")}</>}
          </Row>
          <Row ok={status.secrets ? secret("XAI_API_KEY") : null} title="Grok (assistant and Grok bots)">
            {status.secrets == null ? "Couldn't check." : secret("XAI_API_KEY") ? "XAI_API_KEY is set." : <>Add XAI_API_KEY under Edge Functions → Secrets{dash("functions/secrets")}</>}
          </Row>
          <Row ok={!!scheduled} title="Schedules (calendars every 15 min, bots every 5)">
            {scheduled ? (
              <>
                Running.{" "}
                {status.lastCalendarSync ? <>Calendars last synced <Time iso={status.lastCalendarSync} />. </> : null}
                {status.lastBotRun ? <>A bot last ran <Time iso={status.lastBotRun} />.</> : null}
              </>
            ) : status.cron == null ? (
              "pg_cron isn't on this database."
            ) : (
              "Add the scheduler's two Vault values (mcfly_project_url, mcfly_cron_secret); see docs/ADMIN.md."
            )}
          </Row>
          <Row ok={null} title="Sign-ups">
            The first account is the admin. Turn new sign-ups off under Authentication → Sign In / Up{dash("auth/providers")}
          </Row>
        </ul>
      </CardContent>
    </Card>
  );
}
