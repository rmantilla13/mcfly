"use client";

import { useEffect, useState, type ReactNode } from "react";
import StatusMark from "@/components/reactbits/StatusMark";

// A button's glyph while it runs something (Run now, Sync now): React Bits'
// StatusMark turning as the action is pending, then its check — or its
// cross — held for a moment once the result is in, then the button's own
// icon again. `result` is useFormAction's: each submit's is a new object,
// and one is shown until its moment is up.

const SHOW_MS = 1800;

type Result = { ok: boolean } | null | undefined;

export function RunMark({ pending, result, idle, size = 16 }: { pending: boolean; result: Result; idle: ReactNode; size?: number }) {
  const [shown, setShown] = useState<Result>(null);
  useEffect(() => {
    if (!result || shown === result) return;
    const t = setTimeout(() => setShown(result), SHOW_MS);
    return () => clearTimeout(t);
  }, [result, shown]);
  const status = pending ? "running" : result && shown !== result ? (result.ok ? "done" : "failed") : null;
  return status ? <StatusMark status={status} size={size} data-icon="inline-start" className="shrink-0" /> : idle;
}
