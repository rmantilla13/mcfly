"use client";

import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import type { FormAction } from "@/lib/action-result";

export function LoginForm({ action, next }: { action: FormAction; next: string }) {
  const { result, pending, submit } = useFormAction(action);
  const failed = result && !result.ok;
  return (
    <form onSubmit={submit}>
      <input type="hidden" name="next" value={next} />
      <FieldGroup>
        <Field data-invalid={failed || undefined}>
          <FieldLabel htmlFor="email">Email</FieldLabel>
          <Input id="email" name="email" type="email" autoComplete="username" required autoFocus aria-invalid={failed || undefined} />
        </Field>
        <Field data-invalid={failed || undefined}>
          <FieldLabel htmlFor="password">Password</FieldLabel>
          <Input id="password" name="password" type="password" autoComplete="current-password" required aria-invalid={failed || undefined} />
        </Field>
        {failed ? <FieldError>{result.error}</FieldError> : null}
        <Button type="submit" size="lg" disabled={pending}>
          {pending ? <Spinner data-icon="inline-start" /> : null}
          {pending ? "Signing in…" : "Sign in"}
        </Button>
      </FieldGroup>
    </form>
  );
}
