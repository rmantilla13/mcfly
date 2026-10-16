# How McFly answers

McFly's answers are built to be taken in fast: on a phone in one glance, or
from across a room in one breath. Three skills in the `assistant` function
(`backend/supabase/functions/assistant/skills.ts`) say how, and every client
draws what they ask for. The prompt is composed from them by mode, so Claude
and Grok get the same rules.

| Skill | In which modes | What it says |
|---|---|---|
| `brief` | all of them | What to say: the answer first, only what changes what the person does next, figures as a person says them, ordered by urgency, five things at most |
| `layout` | `read` (the full-screen Ask) | How it looks at a phone's width: bold names, one fact a line, headings named by what to do, tagged items, a stats block, narrow tables only |
| `spoken` | `quick` (the Pi, the phone's voice screen) | One or two sentences in one breath, names rather than tickers, nothing you couldn't say across a room |

`brief` holds no formatting rules on purpose: the Pi's chat bubble is plain
text and `quick` is spoken, so asking those for bold would put asterisks on
the screen or in the voice. Only `read` is asked for shape.

## What `layout` asks for

Standard Markdown, plus two shapes of McFly's own.

**A tagged list item** opens with a word or two in square brackets (1 to 24
characters), then a space. A list with tags is drawn as one card, a row per
item: the bold name first, the tag as a chip at the row's end (so the names
line up whatever the chips say), and the detail under them across the
card's width. A client that predates tags shows them as bracketed text.

In any list, an item that opens with a bold name followed by a dash or a
colon (`**Armra proposal** — due Monday`) sets the name on a line of its
own and the detail under it, starting with a capital.

```
- [Mon] **Armra proposal** — 2–3 proofs of concept for Todd
- [Waiting] **Jamie Umpherson** — interview scheduling, likely next week
- [Overdue] **J446 Eric Hinman** — confirm the end card
```

The colour comes from the tag's first word ("Waiting on Sophie" is amber):

| Word | Chip colour |
|---|---|
| down, overdue, late, blocked, missed, off | red (the theme's loss colour) |
| up, done, paid, sent, shipped, on | green (the theme's gain colour) |
| watch, waiting, pending, soon, risk | amber |
| anything else (a day, a time) | the accent |

**A stats block** is a fence marked `stats`, one figure per line as
`label | value | tone`. The tone is `up`, `down` or `watch`, or left out.
The clients draw a tile per line, two or three to a row. A line without a
pipe is skipped. A client that predates it shows the block as code.

````
```stats
Open edits | 5
Due Monday | 1 | watch
Portfolio | $118.4k | up
```
````

**Tables** are for figures and short names only: at most three columns, no
sentence in a cell. Anything wordier is a tagged list. The clients still
draw any table the model writes: a grid while it fits the page, and a card
per row when it doesn't (on a phone, or with more than three columns or a
cell over 24 characters). A card's title is the row's first cell, and the
other cells sit under it labelled with the header's words. With two columns
the label is left out: the card is a name and what it says.

`###` headings are drawn as small spaced capitals with a hairline after
them, the answer's first paragraph a size larger than the rest, and a word
too long for the line (a link, a path, a file name) breaks where it has to.
Nothing in an answer is ever wider than the screen. Stat figures never
break: short ones are large, long ones shrink to fit their tile.

## Where each piece lives

| Piece | Backend | Apple (McFlyKit + app) | Console |
|---|---|---|---|
| The rules | `assistant/skills.ts`, composed in `helpers.ts` (`systemPrompt`) | | |
| Parsing tags and stats | | `Markdown.swift` (`ListItem.tag`, `.stats`) | `lib/markdown.ts` (`tag`, `"stats"`) |
| Drawing | | `Components.swift` (`AnswerMarkdown`) | `components/ask/Markdown.tsx` |
| Reading aloud | | | `plainText` turns a tag into "Mon: …" and a stat into "Open edits 5." |
| Tests | `helpers.test.ts` | `MarkdownTests.swift` | `tests/markdown.test.mjs` |

## Changing a skill

Edit the text in `skills.ts` and keep its test in `helpers.test.ts` passing.
A new shape needs a parser and a renderer on both clients first, then the
function deployed: an app that predates the shape shows its Markdown source.
Deploy the function after the TestFlight build and the console that draw it,
or together with them.
