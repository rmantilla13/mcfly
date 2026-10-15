"use client";

import { MonitorIcon, PencilIcon, ShieldOffIcon } from "lucide-react";
import { useId, useState } from "react";
import { toast } from "sonner";
import { DisplaySettingsDialog } from "@/components/DisplaySettingsDialog";
import { ConfirmAction } from "@/components/ConfirmAction";
import { EmptyState, Time } from "@/components/bits";
import { useFormAction } from "@/components/useFormAction";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { FieldError } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import type { FormAction } from "@/lib/action-result";
import { isOnline } from "@/lib/format";
import type { Device } from "@/lib/types";

export function DevicesTable({ devices, renameAction, revokeAction, settingsAction }: { devices: Device[]; renameAction: FormAction; revokeAction: FormAction; settingsAction: FormAction }) {
  if (devices.length === 0) {
    return (
      <EmptyState title="No displays paired" icon={<MonitorIcon />}>
        Enter the 6-digit code a display shows, in the card beside this one.
      </EmptyState>
    );
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead className="pl-4">Display</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Last seen</TableHead>
          <TableHead className="max-xl:hidden">Paired</TableHead>
          <TableHead className="pr-4 text-right">
            <span className="sr-only">Actions</span>
          </TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {devices.map((d) => (
          <DeviceRow key={d.id} device={d} renameAction={renameAction} revokeAction={revokeAction} settingsAction={settingsAction} />
        ))}
      </TableBody>
    </Table>
  );
}

function DeviceRow({ device, renameAction, revokeAction, settingsAction }: { device: Device; renameAction: FormAction; revokeAction: FormAction; settingsAction: FormAction }) {
  const [editing, setEditing] = useState(false);
  const id = useId();
  const { result, pending, submit, reset } = useFormAction(renameAction, (res) => {
    setEditing(false);
    if (res?.ok && res.message) toast.success(res.message);
  });
  const online = isOnline(device.last_seen_at);

  return (
    <TableRow>
      <TableCell className="pl-4">
        {editing ? (
          <form
            onSubmit={submit}
            className="flex flex-col gap-1"
            onReset={() => {
              setEditing(false);
              reset();
            }}
          >
            <input type="hidden" name="device_id" value={device.id} />
            <div className="flex items-center gap-2">
              <Input
                id={`${id}-name`}
                name="name"
                defaultValue={device.name}
                required
                maxLength={80}
                autoFocus
                onFocus={(e) => e.currentTarget.select()}
                className="w-56"
                aria-label="Display name"
              />
              <Button type="submit" size="sm" disabled={pending}>
                {pending ? <Spinner data-icon="inline-start" /> : null}
                Save
              </Button>
              <Button type="reset" variant="ghost" size="sm">
                Cancel
              </Button>
            </div>
            {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          </form>
        ) : (
          <div className="flex flex-col">
            <span className="font-medium">{device.name}</span>
            <span className="font-mono text-xs text-muted-foreground" title={device.id}>
              {device.id.slice(0, 8)}
            </span>
          </div>
        )}
      </TableCell>
      <TableCell>{online ? <Badge variant="success">Online</Badge> : <Badge variant="outline">Offline</Badge>}</TableCell>
      <TableCell>
        <Time iso={device.last_seen_at} />
      </TableCell>
      <TableCell className="max-xl:hidden">
        <Time iso={device.created_at} />
      </TableCell>
      <TableCell className="pr-4">
        <div className="flex flex-wrap justify-end gap-1.5">
          <DisplaySettingsDialog device={device} action={settingsAction} />
          <Button variant="outline" size="sm" onClick={() => setEditing(true)} disabled={editing}>
            <PencilIcon data-icon="inline-start" />
            Rename
          </Button>
          <ConfirmAction
            action={revokeAction}
            fields={{ device_id: device.id }}
            title={`Revoke ${device.name}?`}
            description="The display's sign-in is removed. Within a minute it stops showing the feeds and shows a pairing code again."
            confirmLabel="Revoke display"
            tone="danger"
            trigger={
              <Button variant="destructive" size="sm">
                <ShieldOffIcon data-icon="inline-start" />
                Revoke
              </Button>
            }
          />
        </div>
      </TableCell>
    </TableRow>
  );
}
