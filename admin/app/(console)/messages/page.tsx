import type { Metadata } from "next";
import {
  pollMessagesAction,
  readMessagesAction,
  saveMessageNamesAction,
  sendMessageAction,
  setAwayAction,
  testNotificationAction,
  voiceNoteUrlAction,
} from "@/app/(console)/actions";
import { MessagesThread } from "@/components/MessagesThread";
import { PageHeader } from "@/components/PageHeader";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { getAway, getMessageNames, getSettings, listMessages, requireAdmin } from "@/lib/data";
import { DataError } from "@/lib/errors";
import type { Message } from "@/lib/messages";

export const metadata: Metadata = { title: "Messages" };

export default async function MessagesPage() {
  await requireAdmin();
  let messages: Message[] = [];
  let problem: string | null = null;
  try {
    messages = await listMessages();
  } catch (err) {
    if (!(err instanceof DataError)) throw err;
    problem = err.message;
  }
  const [names, settings, away] = await Promise.all([getMessageNames(), getSettings(), getAway()]);
  return (
    <>
      <PageHeader
        title="Messages"
        subtitle="Home and you: what the family writes on the display, and your replies, which show on it within seconds."
      />
      {problem ? (
        <Alert variant="destructive" className="mb-6">
          <AlertTitle>Messages aren&apos;t ready</AlertTitle>
          <AlertDescription>{problem}</AlertDescription>
        </Alert>
      ) : null}
      <MessagesThread
        initial={messages}
        names={names}
        away={away}
        timeZone={settings.timezone}
        actions={{
          poll: pollMessagesAction,
          send: sendMessageAction,
          read: readMessagesAction,
          saveNames: saveMessageNamesAction,
          setAway: setAwayAction,
          test: testNotificationAction,
          voiceNoteUrl: voiceNoteUrlAction,
        }}
      />
    </>
  );
}
