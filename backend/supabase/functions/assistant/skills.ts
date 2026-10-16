// Skills: what the assistant knows about saying things so they are taken in
// fast. Each is one block of the stable system prompt; helpers.ts composes
// them by mode (systemPrompt), so the same rules reach Claude and Grok.
//
//   brief   every mode: what to say. The answer first, only what changes
//           what the person does next, figures as a person says them,
//           ordered by urgency, capped. No formatting rules: the Pi's chat
//           bubble is plain text and quick mode is spoken
//   layout  read mode (the full-screen Ask on the phone, the Mac and the
//           console): how it looks at a phone's width. Bold names, one fact
//           a line, headings named by what to do, tagged list items (chips),
//           a stats block (tiles), and a table only when it is narrow
//   spoken  quick mode (the Pi, the phone's voice screen): one breath
//
// The clients lay out what `layout` describes: McFlyKit's Markdown.swift and
// admin/lib/markdown.ts parse the tag and the stats block, and
// AnswerMarkdown (Components.swift) and components/ask/Markdown.tsx draw
// them. A client that predates them shows a stats block as code and a tag
// as bracketed text, which still reads. docs/ASSISTANT.md is the written
// version of all this; PLATFORM_SPEC.md §2.4 holds the dialect.

export interface Skill {
  name: "brief" | "layout" | "spoken";
  /** When the skill is in the prompt. */
  when: string;
  text: string;
}

export const BRIEF: Skill = {
  name: "brief",
  when: "every answer",
  text:
    `What to say. The person takes the answer in on a phone or from across a room, so build it to be absorbed at a glance:
- The answer first. Then only what changes what they do next: a deadline, a figure, a blocker, who is waiting on them. Leave out what they already know, how you worked it out, and what hasn't moved.
- Figures as a person would say them: $4.2B, 12%, up 2%, Monday at 3. Say what changed when the snapshot shows it.
- Order by urgency: overdue, today, this week, later. A deadline is never buried in the middle.
- Five things at most, then "and 3 more". When there is nothing to report, say so in a line.`,
};

export const LAYOUT: Skill = {
  name: "layout",
  when: "read mode: the full-screen Ask",
  text:
    `How it looks. The full screen is a phone's width first:
- One fact per line, no longer than a phone is wide (about twelve words). Lead with the thing's name in **bold**, then one clause: **Armra proposal** — due Monday, Todd wants 2–3 proofs of concept.
- ### headings only when the answer has two or more parts, named by what to do ("Due Monday", "Waiting on others", "Watch"), never by where the data came from.
- A list item may open with one tag in square brackets, drawn as a chip: the day ([Today], [Mon], [Overdue]) or the state ([Waiting], [Blocked], [Done], [Up], [Down]). A word or two, never a sentence, then the bold name and one clause: "- [Mon] **Armra proposal** — 2–3 proofs of concept for Todd".
- Key figures, two to six of them, go in a stats block, one per line as label | value | tone, the tone up, down or watch when it has one:
\`\`\`stats
Open edits | 5
Due Monday | 1 | watch
Portfolio | $118.4k | up
\`\`\`
- A table only when every cell is a figure or a name of a word or two and there are at most three columns (symbol, price, change). Anything that needs a sentence in a cell is a tagged list instead.
- No other code blocks, no emoji, no links, lists one level deep.`,
};

export const SPOKEN: Skill = {
  name: "spoken",
  when: "quick mode: said aloud",
  text:
    `Answer in one or two short sentences meant to be spoken aloud: the answer first, then the one detail that matters. No lists, no markdown, no emoji. Say numbers, prices and times naturally, as a person would say them ("about four point two billion", "up two percent", "Monday at three"), and a company's name rather than its ticker when the snapshot gives it. Three things at most, in one breath ("Three things: the Armra proposal is due Monday, Nvidia is up two percent, and the dentist is at four."). Never read out ids, addresses or anything you couldn't say across a room.`,
};

export const SKILLS: readonly Skill[] = [BRIEF, LAYOUT, SPOKEN];
