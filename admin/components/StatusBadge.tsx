import StatusMark from "@/components/reactbits/StatusMark";
import { Badge } from "@/components/ui/badge";

// A push's outcome: the word, with React Bits' StatusMark drawn in the
// badge's own ink beside it. A file of its own, not in bits.tsx: StatusMark
// animates with motion, and every client component a server file imports
// ships on each page that imports that file, whether it renders it or not.
// Here, only the pages with a push log carry it.
export function StatusBadge({ status }: { status: "ok" | "error" }) {
  const mark = <StatusMark status={status === "ok" ? "done" : "failed"} size={12} doneColor="currentColor" errorColor="currentColor" aria-hidden="true" />;
  return status === "ok" ? (
    <Badge variant="success">
      {mark}
      ok
    </Badge>
  ) : (
    <Badge variant="destructive">
      {mark}
      error
    </Badge>
  );
}
