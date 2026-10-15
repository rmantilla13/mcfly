// What server actions hand back to their forms (via useFormAction).
//
// `key` is an agent key, carried back exactly once (create, rotate); the
// form shows it and nothing stores it. `deviceId` comes back from pairing.
export type ActionResult =
  | { ok: true; message?: string; key?: string; slug?: string; deviceId?: string }
  | { ok: false; error: string }
  | null;

export type FormAction = (prev: ActionResult, formData: FormData) => Promise<ActionResult>;
