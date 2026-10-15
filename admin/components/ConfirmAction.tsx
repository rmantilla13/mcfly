"use client";

import { useId, useState, type ReactNode } from "react";
import { toast } from "sonner";
import { useFormAction } from "@/components/useFormAction";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import type { ActionResult, FormAction } from "@/lib/action-result";

type Props = {
  action: FormAction;
  fields: Record<string, string>; // hidden inputs sent with the form
  title: string;
  description?: ReactNode;
  confirmLabel: string;
  tone?: "default" | "danger";
  typeToConfirm?: { value: string; label: string; caseInsensitive?: boolean };
  // Either a trigger (the button that opens the dialog) or a controlled
  // open state, for callers that open it from a menu.
  trigger?: ReactNode;
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
  onSuccess?: (result: ActionResult) => void;
};

// An AlertDialog that submits a server action, optionally after the admin
// types a name to confirm. Toasts the result's message on success.
export function ConfirmAction(props: Props) {
  const [uncontrolledOpen, setUncontrolledOpen] = useState(false);
  const controlled = props.open !== undefined;
  const open = controlled ? props.open! : uncontrolledOpen;
  const setOpen = (next: boolean) => {
    if (!controlled) setUncontrolledOpen(next);
    props.onOpenChange?.(next);
  };

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      {props.trigger ? <AlertDialogTrigger asChild>{props.trigger}</AlertDialogTrigger> : null}
      <AlertDialogContent>
        {open ? <ConfirmForm {...props} close={() => setOpen(false)} /> : null}
      </AlertDialogContent>
    </AlertDialog>
  );
}

function ConfirmForm({
  action,
  fields,
  title,
  description,
  confirmLabel,
  tone = "default",
  typeToConfirm,
  onSuccess,
  close,
}: Props & { close: () => void }) {
  const [typed, setTyped] = useState("");
  const inputId = useId();
  const { result, pending, submit } = useFormAction(action, (res) => {
    close();
    if (res?.ok && res.message) toast.success(res.message);
    onSuccess?.(res);
  });

  const typedOk =
    !typeToConfirm ||
    (typeToConfirm.caseInsensitive
      ? typed.trim().toLowerCase() === typeToConfirm.value.trim().toLowerCase()
      : typed.trim() === typeToConfirm.value.trim());

  return (
    <form onSubmit={submit} className="contents">
      <AlertDialogHeader>
        <AlertDialogTitle>{title}</AlertDialogTitle>
        {description ? <AlertDialogDescription>{description}</AlertDialogDescription> : null}
      </AlertDialogHeader>
      {Object.entries(fields).map(([name, value]) => (
        <input key={name} type="hidden" name={name} value={value} />
      ))}
      {typeToConfirm ? (
        <Field data-invalid={result && !result.ok ? true : undefined}>
          <FieldLabel htmlFor={inputId}>{typeToConfirm.label}</FieldLabel>
          <Input
            id={inputId}
            name="confirm"
            value={typed}
            onChange={(e) => setTyped(e.target.value)}
            autoComplete="off"
            spellCheck={false}
            autoFocus
            aria-invalid={result && !result.ok ? true : undefined}
          />
        </Field>
      ) : null}
      {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
      <AlertDialogFooter>
        <AlertDialogCancel type="button" onClick={close}>
          Cancel
        </AlertDialogCancel>
        <Button type="submit" variant={tone === "danger" ? "destructive" : "default"} disabled={pending || !typedOk}>
          {pending ? <Spinner data-icon="inline-start" /> : null}
          {pending ? "Working…" : confirmLabel}
        </Button>
      </AlertDialogFooter>
    </form>
  );
}
