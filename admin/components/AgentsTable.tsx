"use client";

import { BotIcon, KeyRoundIcon, MoreHorizontalIcon, PencilIcon, ShieldOffIcon, Trash2Icon } from "lucide-react";
import { useId, useState } from "react";
import { toast } from "sonner";
import { ConfirmAction } from "@/components/ConfirmAction";
import { KeyReveal } from "@/components/KeyReveal";
import { ColorField, KindSelect } from "@/components/NewAgentForm";
import { SCOPE_INFO, ScopeSwitches } from "@/components/agents/ScopeSwitches";
import { EmptyState, KindBadge, Swatch, Time, numCell } from "@/components/bits";
import { useFormAction } from "@/components/useFormAction";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import type { FormAction } from "@/lib/action-result";
import { formatNumber } from "@/lib/format";
import type { AgentRow, AgentScope } from "@/lib/types";

type Actions = { rotate: FormAction; update: FormAction; revoke: FormAction; remove: FormAction };
type Pending = { type: "edit" | "rotate" | "revoke" | "delete"; agent: AgentRow } | null;

export function AgentsTable({ agents, actions, baseUrl }: { agents: AgentRow[]; actions: Actions; baseUrl: string }) {
  const [pending, setPending] = useState<Pending>(null);
  // A rotated key, shown above the table until the page is left.
  const [reveal, setReveal] = useState<{ agent: AgentRow; key: string } | null>(null);
  const close = () => setPending(null);

  return (
    <div className="flex flex-col gap-5">
      {reveal ? <KeyReveal agentName={reveal.agent.name} kind={reveal.agent.kind} apiKey={reveal.key} baseUrl={baseUrl} /> : null}

      {agents.length === 0 ? (
        <EmptyState title="No agents yet" icon={<BotIcon />}>
          Create one above; its key is shown once, with a push to try.
        </EmptyState>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="pl-4">Agent</TableHead>
              <TableHead>Kind</TableHead>
              <TableHead className="max-lg:hidden">May read</TableHead>
              <TableHead>Key</TableHead>
              <TableHead className={numCell}>Pushes, 7d</TableHead>
              <TableHead>Last push</TableHead>
              <TableHead>Last error</TableHead>
              <TableHead className="max-xl:hidden">Created</TableHead>
              <TableHead className="w-12 pr-4">
                <span className="sr-only">Actions</span>
              </TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {agents.map((a) => (
              <TableRow key={a.id} className={a.revoked_at ? "text-muted-foreground" : undefined}>
                <TableCell className="pl-4">
                  <div className="flex items-center gap-2.5">
                    <Swatch color={a.color} className="size-3.5" />
                    <div className="min-w-0">
                      <div className="truncate font-medium text-foreground">{a.name}</div>
                      <div className="font-mono text-xs text-muted-foreground">{a.slug}</div>
                    </div>
                  </div>
                </TableCell>
                <TableCell>
                  <KindBadge kind={a.kind} />
                </TableCell>
                <TableCell className="max-lg:hidden">
                  {a.scopes.length ? (
                    <div className="flex flex-wrap gap-1">
                      {a.scopes.map((sc) => (
                        <Badge key={sc} variant="outline" className="font-normal">
                          {SCOPE_INFO.find((x) => x.scope === sc)?.label ?? sc}
                        </Badge>
                      ))}
                    </div>
                  ) : (
                    <span className="text-muted-foreground">Push only</span>
                  )}
                </TableCell>
                <TableCell>
                  {a.revoked_at ? (
                    <Badge variant="warning">Revoked</Badge>
                  ) : a.key_prefix ? (
                    <div className="flex flex-col">
                      <code className="font-mono text-xs">{a.key_prefix}…</code>
                      <span className="text-xs text-muted-foreground">
                        made <Time iso={a.key_created_at} />
                      </span>
                    </div>
                  ) : (
                    <Badge variant="outline">No key</Badge>
                  )}
                </TableCell>
                <TableCell className={numCell}>{formatNumber(a.pushes_7d)}</TableCell>
                <TableCell>
                  <Time iso={a.last_seen_at} />
                </TableCell>
                <TableCell className="max-w-[180px]">
                  {a.last_error ? (
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <span className="block truncate text-destructive">{a.last_error}</span>
                      </TooltipTrigger>
                      <TooltipContent>{a.last_error}</TooltipContent>
                    </Tooltip>
                  ) : (
                    <span className="text-muted-foreground">—</span>
                  )}
                </TableCell>
                <TableCell className="max-xl:hidden">
                  <Time iso={a.created_at} />
                </TableCell>
                <TableCell className="pr-4 text-right">
                  <DropdownMenu>
                    <DropdownMenuTrigger asChild>
                      <Button variant="ghost" size="icon-sm" aria-label={`Actions for ${a.name}`}>
                        <MoreHorizontalIcon />
                      </Button>
                    </DropdownMenuTrigger>
                    <DropdownMenuContent align="end" className="w-48">
                      <DropdownMenuGroup>
                        <DropdownMenuItem onSelect={() => setPending({ type: "edit", agent: a })}>
                          <PencilIcon />
                          Edit
                        </DropdownMenuItem>
                        <DropdownMenuItem onSelect={() => setPending({ type: "rotate", agent: a })}>
                          <KeyRoundIcon />
                          {a.revoked_at ? "Rotate key (revive)" : "Rotate key"}
                        </DropdownMenuItem>
                        {a.revoked_at ? null : (
                          <DropdownMenuItem onSelect={() => setPending({ type: "revoke", agent: a })}>
                            <ShieldOffIcon />
                            Revoke
                          </DropdownMenuItem>
                        )}
                      </DropdownMenuGroup>
                      <DropdownMenuSeparator />
                      <DropdownMenuGroup>
                        <DropdownMenuItem variant="destructive" onSelect={() => setPending({ type: "delete", agent: a })}>
                          <Trash2Icon />
                          Delete
                        </DropdownMenuItem>
                      </DropdownMenuGroup>
                    </DropdownMenuContent>
                  </DropdownMenu>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      {pending?.type === "edit" ? <EditAgentDialog agent={pending.agent} action={actions.update} close={close} /> : null}

      <ConfirmAction
        open={pending?.type === "rotate"}
        onOpenChange={(o) => !o && close()}
        action={actions.rotate}
        fields={{ agent_id: pending?.agent.id ?? "" }}
        title={pending?.agent.revoked_at ? `Make a new key for ${pending.agent.name}?` : `Rotate ${pending?.agent.name ?? "this agent"}'s key?`}
        description={
          pending?.agent.revoked_at
            ? "The agent is revoked. A new key brings it back; its old key stays dead."
            : "The current key stops working at once. The new one is shown once, here, and the agent needs it before its next push."
        }
        confirmLabel="Rotate key"
        onSuccess={(res) => {
          if (res?.ok && res.key && pending) setReveal({ agent: pending.agent, key: res.key });
        }}
      />
      <ConfirmAction
        open={pending?.type === "revoke"}
        onOpenChange={(o) => !o && close()}
        action={actions.revoke}
        fields={{ agent_id: pending?.agent.id ?? "" }}
        title={`Revoke ${pending?.agent.name ?? "this agent"}?`}
        description="Its key is deleted and its pushes are refused. What it already pushed stays. Rotating the key later brings it back."
        confirmLabel="Revoke"
        tone="danger"
      />
      <ConfirmAction
        open={pending?.type === "delete"}
        onOpenChange={(o) => !o && close()}
        action={actions.remove}
        fields={{ agent_id: pending?.agent.id ?? "", expected: pending?.agent.name ?? "" }}
        title={`Delete ${pending?.agent.name ?? "this agent"}?`}
        description="The agent and everything it pushed (briefs, quotes, reports, its log) are removed for good."
        confirmLabel="Delete agent"
        tone="danger"
        typeToConfirm={{ value: pending?.agent.name ?? "", label: `Type ${pending?.agent.name ?? "the name"} to confirm` }}
      />
    </div>
  );
}

function EditScopes({ initial, idPrefix }: { initial: AgentScope[]; idPrefix: string }) {
  const [value, setValue] = useState<AgentScope[]>(initial);
  return <ScopeSwitches value={value} onChange={setValue} idPrefix={idPrefix} />;
}

function EditAgentDialog({ agent, action, close }: { agent: AgentRow; action: FormAction; close: () => void }) {
  const id = useId();
  const { result, pending, submit } = useFormAction(action, (res) => {
    close();
    if (res?.ok && res.message) toast.success(res.message);
  });
  return (
    <Dialog open onOpenChange={(o) => !o && close()}>
      <DialogContent>
        <form onSubmit={submit} className="contents">
          <DialogHeader>
            <DialogTitle>Edit {agent.name}</DialogTitle>
            <DialogDescription>The slug ({agent.slug}) and the key stay as they are.</DialogDescription>
          </DialogHeader>
          <input type="hidden" name="agent_id" value={agent.id} />
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${id}-name`}>Name</FieldLabel>
              <Input id={`${id}-name`} name="name" defaultValue={agent.name} required maxLength={80} autoFocus />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${id}-kind`}>Kind</FieldLabel>
              <KindSelect name="kind" defaultValue={agent.kind} id={`${id}-kind`} />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${id}-color`}>Color</FieldLabel>
              <ColorField name="color" defaultValue={/^#[0-9a-f]{6}$/i.test(agent.color) ? agent.color.toLowerCase() : "#4f7cf7"} id={`${id}-color`} />
            </Field>
            <Field>
              <FieldLabel>What it may read</FieldLabel>
              <input type="hidden" name="scopes_present" value="1" />
              <EditScopes initial={agent.scopes} idPrefix={id} />
            </Field>
            {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={close}>
              Cancel
            </Button>
            <Button type="submit" disabled={pending}>
              {pending ? <Spinner data-icon="inline-start" /> : null}
              {pending ? "Saving…" : "Save"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
