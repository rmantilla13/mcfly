"use client";

import { SlidersHorizontalIcon } from "lucide-react";
import { useState, type ReactNode } from "react";
import { toast } from "sonner";
import { useFormAction } from "@/components/useFormAction";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Field, FieldError, FieldGroup, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/spinner";
import { Switch } from "@/components/ui/switch";
import type { FormAction } from "@/lib/action-result";
import type { Device, DisplaySettings } from "@/lib/types";

// The display's own settings, edited from the web. The display applies them
// on its next sync (within a minute); changes made on the screen come back
// here the same way. Defaults match the display's own.
const DEFAULTS: Required<Omit<DisplaySettings, "volume">> = {
  screensaver: "ambient",
  backdrop: "mesh",
  darkMode: false,
  animatedTiles: true,
  idleSeconds: 120,
  offAfterSeconds: 0,
  offAtNight: false,
  bedtime: 22 * 60,
  wakeTime: 6 * 60 + 30,
  assistantProvider: "",
  speakReplies: true,
  wakeword: true,
  wakewordModel: "hey_mcfly",
  voice: "af_heart",
  voiceSpeed: 1,
};

const hhmm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="flex flex-col gap-3">
      <h3 className="text-xs font-bold tracking-[0.12em] text-muted-foreground uppercase">{title}</h3>
      {children}
    </div>
  );
}

function Toggle({ name, label, hint, value }: { name: string; label: string; hint?: string; value: boolean }) {
  const [on, setOn] = useState(value);
  return (
    <label className="flex items-center justify-between gap-4 rounded-xl border px-3.5 py-2.5">
      <span>
        <span className="block text-sm font-medium">{label}</span>
        {hint ? <span className="block text-xs text-muted-foreground">{hint}</span> : null}
      </span>
      <input type="hidden" name={name} value={on ? "true" : "false"} />
      <Switch checked={on} onCheckedChange={setOn} aria-label={label} />
    </label>
  );
}

function Choice({ name, label, value, options }: { name: string; label: string; value: string | number; options: [string, string][] }) {
  return (
    <Field>
      <FieldLabel htmlFor={`ds-${name}`}>{label}</FieldLabel>
      <select
        id={`ds-${name}`}
        name={name}
        defaultValue={String(value)}
        className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
      >
        {options.map(([v, l]) => (
          <option key={v} value={v}>
            {l}
          </option>
        ))}
      </select>
    </Field>
  );
}

export function DisplaySettingsDialog({ device, action }: { device: Device; action: FormAction }) {
  const [open, setOpen] = useState(false);
  const s = { ...DEFAULTS, ...device.settings };
  const { result, pending, submit } = useFormAction(action, (res) => {
    setOpen(false);
    if (res?.ok && res.message) toast.success(res.message);
  });
  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <SlidersHorizontalIcon data-icon="inline-start" />
          Customize
        </Button>
      </DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-xl">
        <form onSubmit={submit} className="contents">
          <DialogHeader>
            <DialogTitle>Customize {device.name}</DialogTitle>
            <DialogDescription>
              {Object.keys(device.settings).length
                ? "The display picks changes up within a minute. Changes made on its own Settings show up here too."
                : "This display hasn't reported its settings yet; these are the defaults. It sends its own on its next sync."}
            </DialogDescription>
          </DialogHeader>
          <input type="hidden" name="device_id" value={device.id} />
          <FieldGroup>
            <Section title="Screen">
              <div className="grid grid-cols-2 gap-3 max-sm:grid-cols-1">
                <Choice
                  name="screensaver"
                  label="Screen saver"
                  value={s.screensaver}
                  options={[["ambient", "Ambient (clock and cards)"], ["headlines", "Headlines"], ["clock", "Clock"]]}
                />
                <Choice
                  name="backdrop"
                  label="Backdrop (Ambient and Clock)"
                  value={s.backdrop}
                  options={[
                    ["mesh", "Mesh (gradient, an aurora at night)"],
                    ["arc", "Arc (an aurora across the sky)"],
                    ["ribbons", "Ribbons (thin curtains, folding)"],
                    ["dawn", "Dawn (a horizon glow)"],
                    ["silk", "Silk (satin folds)"],
                    ["pillars", "Pillars (rays from the ground)"],
                  ]}
                />
                <Choice
                  name="idleSeconds"
                  label="Screen saver after"
                  value={s.idleSeconds}
                  options={[["60", "1 minute"], ["120", "2 minutes"], ["300", "5 minutes"], ["600", "10 minutes"], ["1800", "30 minutes"]]}
                />
              </div>
              <Toggle name="darkMode" label="Dark mode" value={s.darkMode} />
              <Toggle name="animatedTiles" label="Animated tiles" hint="The colors on Home and the saver drift slowly" value={s.animatedTiles} />
            </Section>
            <Section title="Sleep">
              <Choice
                name="offAfterSeconds"
                label="Turn the screen off after"
                value={s.offAfterSeconds}
                options={[["0", "Never"], ["900", "15 minutes"], ["1800", "30 minutes"], ["3600", "1 hour"], ["7200", "2 hours"]]}
              />
              <Toggle name="offAtNight" label="Off overnight" hint="A tap still wakes it" value={s.offAtNight} />
              <div className="grid grid-cols-2 gap-3">
                <Field>
                  <FieldLabel htmlFor="ds-bedtime">Bedtime</FieldLabel>
                  <Input id="ds-bedtime" name="bedtime" type="time" defaultValue={hhmm(s.bedtime)} required />
                </Field>
                <Field>
                  <FieldLabel htmlFor="ds-wake">Wake up</FieldLabel>
                  <Input id="ds-wake" name="wakeTime" type="time" defaultValue={hhmm(s.wakeTime)} required />
                </Field>
              </div>
            </Section>
            <Section title="Assistant and voice">
              <Choice
                name="assistantProvider"
                label="Answers from"
                value={s.assistantProvider}
                options={[["", "The account's choice"], ["claude", "Claude"], ["grok", "Grok"]]}
              />
              <Toggle name="wakeword" label="Wake word" hint="Needs the voice service and a USB mic" value={s.wakeword} />
              <div className="grid grid-cols-2 gap-3 max-sm:grid-cols-1">
                <Choice
                  name="wakewordModel"
                  label="Wake word"
                  value={s.wakewordModel}
                  options={[
                    ["hey_mcfly", "“Hey McFly”"],
                    ["hey_jarvis", "“Hey Jarvis”"],
                    ["alexa", "“Alexa”"],
                    ["hey_mycroft", "“Hey Mycroft”"],
                    ["hey_rhasspy", "“Hey Rhasspy”"],
                  ]}
                />
                <Choice
                  name="voiceSpeed"
                  label="Speaking speed"
                  value={s.voiceSpeed}
                  options={[["0.85", "Slower"], ["1", "Normal"], ["1.15", "Faster"], ["1.3", "Fast"]]}
                />
              </div>
              <Choice
                name="voice"
                label="Voice (Homestead's)"
                value={s.voice}
                options={[["af_heart", "Heart"], ["af_bella", "Bella"], ["am_michael", "Michael"], ["am_fenrir", "Fenrir"]]}
              />
              <Toggle name="speakReplies" label="Spoken replies" value={s.speakReplies} />
            </Section>
            {result && !result.ok ? <FieldError>{result.error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>
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
