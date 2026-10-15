"use client";

import { CheckCircle2Icon, MonitorIcon } from "lucide-react";
import { useId, useState } from "react";
import { toast } from "sonner";
import { useFormAction } from "@/components/useFormAction";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Field, FieldDescription, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import type { FormAction } from "@/lib/action-result";
import { CODE_LENGTH, formatCode, isCompleteCode, sanitizeCode } from "@/lib/pairing";

// The claim form: the 6 digits a display shows, and a name for it. Submits
// to the pair-device edge function (claim) as the signed-in admin.
export function PairForm({ action, initialCode = "", autoFocus }: { action: FormAction; initialCode?: string; autoFocus?: boolean }) {
  const id = useId();
  const [code, setCode] = useState(sanitizeCode(initialCode));
  const [paired, setPaired] = useState<{ deviceId: string; code: string } | null>(null);
  const { result, pending, submit } = useFormAction(action, (res, form) => {
    if (!res?.ok || !res.deviceId) return;
    setPaired({ deviceId: res.deviceId, code });
    toast.success(res.message ?? "Display paired.");
    form.reset();
    setCode("");
  });

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
            <Input
              id={`${id}-code`}
              name="code"
              value={code}
              onChange={(e) => setCode(sanitizeCode(e.target.value))}
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={CODE_LENGTH}
              placeholder="123456"
              required
              autoFocus={autoFocus}
              className="w-40 font-mono text-lg tracking-[0.3em]"
              aria-invalid={result && !result.ok ? true : undefined}
            />
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
