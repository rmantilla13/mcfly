"use client";

import { cn } from "cn";
import { useState } from "react";
import SquishSwitch from "@/components/reactbits/SquishSwitch";

// The console's switch: React Bits' SquishSwitch (components/reactbits), the
// thumb stretching as it goes and squashing as it lands, behind the props of
// the shadcn/Radix Switch it replaces — checked, defaultChecked,
// onCheckedChange, disabled, name and value, id, aria-label, the two sizes —
// so the forms and labels around it stay as they were. A named switch
// inside a form submits as a checkbox does (Radix kept a hidden input of its
// own for that); the control carries data-state, which the agent scope cards
// style against. The thumb is the page's background in the light scheme and
// its foreground in the dark, as shadcn's was.

const SIZES = {
  default: { width: 32, height: 18, inset: 2 },
  sm: { width: 24, height: 14, inset: 2 },
};

export function Switch({
  className,
  size = "default",
  checked,
  defaultChecked,
  onCheckedChange,
  disabled,
  name,
  value = "on",
  id,
  "aria-label": ariaLabel,
  "aria-labelledby": ariaLabelledBy,
  "aria-describedby": ariaDescribedBy,
}: {
  className?: string;
  size?: "sm" | "default";
  checked?: boolean;
  defaultChecked?: boolean;
  onCheckedChange?: (checked: boolean) => void;
  disabled?: boolean;
  name?: string;
  value?: string;
  id?: string;
  "aria-label"?: string;
  "aria-labelledby"?: string;
  "aria-describedby"?: string;
}) {
  const [inner, setInner] = useState(defaultChecked ?? false);
  const on = checked ?? inner;
  const change = (next: boolean) => {
    if (checked === undefined) setInner(next);
    onCheckedChange?.(next);
  };
  return (
    <span
      data-slot="switch"
      data-size={size}
      className={cn(
        "relative inline-flex shrink-0 [--switch-thumb:var(--background)] [--switch-thumb-on:var(--background)] dark:[--switch-thumb:var(--foreground)] dark:[--switch-thumb-on:var(--primary-foreground)]",
        className,
      )}
    >
      <SquishSwitch
        id={id}
        checked={on}
        onChange={change}
        disabled={disabled}
        ariaLabel={ariaLabel}
        ariaLabelledBy={ariaLabelledBy}
        ariaDescribedBy={ariaDescribedBy}
        trackColor="var(--input)"
        trackOnColor="var(--primary)"
        thumbColor="var(--switch-thumb)"
        thumbOnColor="var(--switch-thumb-on)"
        radius={99}
        {...SIZES[size]}
      />
      {name ? <input type="checkbox" name={name} value={value} checked={on} disabled={disabled} readOnly hidden tabIndex={-1} aria-hidden="true" /> : null}
    </span>
  );
}
