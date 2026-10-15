"use client";

import { useEffect } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { consoleErrorCopy } from "@/lib/errors";

// Next strips the error message in production. DataError puts its sentence in
// `digest` so it still shows; a numeric digest is Next's hash of an unexpected
// throw, and the text for that stays in the server log.
export default function ConsoleError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    console.error(error);
  }, [error]);
  const copy = consoleErrorCopy(error.digest);

  return (
    <Card className="max-w-2xl">
      <CardHeader>
        <CardTitle>This page couldn&apos;t load</CardTitle>
      </CardHeader>
      <CardContent>
        <Alert variant="destructive">
          <AlertTitle>{copy.message}</AlertTitle>
          {copy.reference ? (
            <AlertDescription>
              Reference: <code className="font-mono">{copy.reference}</code>
            </AlertDescription>
          ) : null}
        </Alert>
      </CardContent>
      <CardFooter>
        <Button type="button" onClick={reset}>
          Try again
        </Button>
      </CardFooter>
    </Card>
  );
}
