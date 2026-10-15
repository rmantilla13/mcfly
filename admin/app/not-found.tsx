import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default function NotFound() {
  return (
    <main className="grid min-h-screen place-items-center px-4 py-12">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Page not found</CardTitle>
          <CardDescription>There is nothing at this address.</CardDescription>
        </CardHeader>
        <CardContent>
          <Button variant="outline" asChild>
            <Link href="/">Back to the console</Link>
          </Button>
        </CardContent>
      </Card>
    </main>
  );
}
