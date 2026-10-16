"use client";

import { LocateFixedIcon } from "lucide-react";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { locationErrorSentence, timeZoneAt } from "@/lib/timezones";

// The time zone from where this browser is: its position (the browser asks
// the person the first time), looked up on Open-Meteo at about a kilometre
// (lib/timezones.ts). Once the site is allowed to know, the field is checked
// against the position on every visit; a zone that differs from the one in
// the field is offered, not written, so saving from a trip can't move the
// display's clock by accident. Nothing is saved until the form is.

type State = { kind: "idle" } | { kind: "locating" } | { kind: "found"; zone: string; applied: boolean } | { kind: "failed"; message: string };

function position(): Promise<GeolocationCoordinates> {
  return new Promise((resolve, reject) => {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      reject(new Error("This browser can't share where it is. Type the zone instead."));
      return;
    }
    navigator.geolocation.getCurrentPosition((p) => resolve(p.coords), (err) => reject(new Error(locationErrorSentence(err.code))), {
      enableHighAccuracy: false,
      maximumAge: 10 * 60_000,
      timeout: 20_000,
    });
  });
}

async function zoneHere(): Promise<string> {
  const { latitude, longitude } = await position();
  return timeZoneAt(latitude, longitude);
}

export function LocateTimeZone({ value, onFound }: { value: string; onFound: (zone: string) => void }) {
  const [state, setState] = useState<State>({ kind: "idle" });

  // Already allowed to know where this browser is: check quietly, offer only.
  useEffect(() => {
    let cancelled = false;
    navigator.permissions
      ?.query({ name: "geolocation" })
      .then(async (status) => {
        if (status.state !== "granted" || cancelled) return;
        const zone = await zoneHere();
        if (!cancelled) setState({ kind: "found", zone, applied: false });
      })
      .catch(() => {
        // No permissions API, or the lookup failed: nothing until the button.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  async function locate() {
    setState({ kind: "locating" });
    try {
      const zone = await zoneHere();
      onFound(zone);
      setState({ kind: "found", zone, applied: true });
    } catch (err) {
      setState({ kind: "failed", message: err instanceof Error ? err.message : "Your location couldn't be found." });
    }
  }

  function apply(zone: string) {
    onFound(zone);
    setState({ kind: "found", zone, applied: true });
  }

  const locating = state.kind === "locating";
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      <Button type="button" variant="outline" size="sm" onClick={locate} disabled={locating}>
        {locating ? <Spinner data-icon="inline-start" /> : <LocateFixedIcon data-icon="inline-start" />}
        {locating ? "Finding where you are…" : "Use my location"}
      </Button>
      {state.kind === "found" && state.zone === value ? (
        <span className="text-sm text-muted-foreground">{state.applied ? "From your location." : "Matches where you are."}</span>
      ) : null}
      {state.kind === "found" && state.zone !== value ? (
        <span className="text-sm text-muted-foreground">
          You&apos;re in {state.zone}.{" "}
          <Button type="button" variant="link" size="sm" className="h-auto px-0" onClick={() => apply(state.zone)}>
            Use it
          </Button>
        </span>
      ) : null}
      {state.kind === "failed" ? <span className="text-sm text-destructive">{state.message}</span> : null}
    </div>
  );
}
