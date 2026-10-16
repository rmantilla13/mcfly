"use client";

import { CheckCircle2Icon, MonitorIcon } from "lucide-react";
import { useEffect, useId, useState } from "react";
import { toast } from "sonner";
import { useFormAction } from "@/components/useFormAction";
import CodeSlots from "@/components/reactbits/CodeSlots";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import type { ActionResult, FormAction } from "@/lib/action-result";
import { CODE_LENGTH, formatCode, isCompleteCode, sanitizeCode } from "@/lib/pairing";

// The claim form: the 6 digits a display shows, and a name for it. Submits
// to the pair-device edge function (claim) as the signed-in admin. The
// digits go into React Bits' CodeSlots: each springs into its slot as it is
// typed or pasted, a refused code drains back out, and a paired one is
// washed over with a check before the slots clear for the next display.
export function PairForm({ action, initialCode = "", autoFocus }: { action: FormAction; initialCode?: string; autoFocus?: boolean }) {
  const id = useId();
  const [code, setCode] = useState(sanitizeCode(initialCode));
  const [paired, setPaired] = useState<{ deviceId: string; code: string } | null>(null);
  const [success, setSuccess] = useState(false);
  // The refused result the digits have already drained for; a new one
  // drains them again.
  const [drained, setDrained] = useState<ActionResult>(null);
  const { result, pending, submit } = useFormAction(action, (res, form) => {
    if (!res?.ok || !res.deviceId) return;
    setPaired({ deviceId: res.deviceId, code });
    toast.success(res.message ?? "Display paired.");
    form.reset();
    setSuccess(true);
  });
  const slots = success ? "success" : result && !result.ok && drained !== result ? "error" : "idle";
  // The check stays a moment, then the slots empty for the next code.
  useEffect(() => {
    if (!success) return;
    const t = setTimeout(() => {
      setSuccess(false);
      setCode("");
    }, 1800);
    return () => clearTimeout(t);
  }, [success]);

  return (
    <div className="flex flex-col gap-4">
      {paired ? (
        <Alert>
          <CheckCircle2Icon />
          <AlertTitle>Paired. The screen switches over within a few seconds.</AlertTitle>
          <AlertDescription>
            Code {formatCode(paired.code)} is now display <code className="font-mono">{paired.deviceId}</code>. It polls for its
            session every 3 seconds, then shows the feeds; rename or revoke it in the list.
          </AlertDescription>
        </Alert>
      ) : null}
      <form onSubmit={submit}>
        <FieldGroup>
          <Field data-invalid={result && !result.ok ? true : undefined}>
            <FieldLabel htmlFor={`${id}-code`}>Code on the display</FieldLabel>
            <CodeSlots
              id={`${id}-code`}
              length={CODE_LENGTH}
              value={code}
              onChange={(next) => {
                setCode(sanitizeCode(next));
                if (slots === "error") setDrained(result);
              }}
              status={slots}
              autoFocus={autoFocus}
              ariaLabel="Code on the display"
              slotSize={44}
              gap={8}
              radius={12}
              accentColor="var(--primary)"
              inkColor="var(--foreground)"
              slotColor="color-mix(in oklab, var(--foreground) 10%, var(--card))"
              digitColor="var(--primary-foreground)"
              dangerColor="var(--destructive)"
              className="font-heading"
            />
            <input type="hidden" name="code" value={code} />
            <FieldDescription>Six digits, shown under the QR code. A code lasts 10 minutes; the display then shows a new one.</FieldDescription>
          </Field>
          <Field>
            <FieldLabel htmlFor={`${id}-name`}>Name</FieldLabel>
            <Input id={`${id}-name`} name="name" maxLength={80} placeholder="Kitchen wall" autoComplete="off" />
            <FieldDescription>Optional. Where the screen hangs; you can rename it later.</FieldDescription>
          </Field>
          {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          <div>
            <Button type="submit" disabled={pending || !isCompleteCode(code)}>
              {pending ? <Spinner data-icon="inline-start" /> : <MonitorIcon data-icon="inline-start" />}
              {pending ? "Pairing…" : "Pair display"}
            </Button>
          </div>
        </FieldGroup>
      </form>
    </div>
  );
}
