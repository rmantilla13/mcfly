// The Markdown the assistant writes in read mode (the full-screen Ask), parsed
// into plain data for components/ask/Markdown.tsx to turn into React
// elements. Never HTML: the answer is grounded in what agents push, so a tag
// in it is text, and a link keeps its words but loses its address.
//
// Covers what the prompt asks for and a little more: headings, paragraphs,
// bulleted and numbered lists (nested by indent), tables, quotes, rules and
// fenced code; inline **bold**, *italic*, ~~struck~~ and `code`. It is fed a
// reply while it streams, so half of anything is fine: an unclosed ** is bold
// to the end of its line, a table's header shows as a paragraph until its
// divider row arrives, an open fence runs to the end. Pure, so
// tests/markdown.test.mjs can check it.
//
// Two shapes are the assistant's own (its `layout` skill, docs/ASSISTANT.md):
// a list item opening with `[Mon]` or `[Blocked]` carries that as its `tag`
// (a chip), and a fence marked `stats` is a "stats" block of label | value |
// tone lines (tiles), not code. McFlyKit's Markdown.swift reads them the
// same way.

export type Inline =
  | { t: "text"; v: string }
  | { t: "strong" | "em" | "del"; c: Inline[] }
  | { t: "code"; v: string }
  | { t: "br" };

// `tag` is there only when the item opened with one: `[Mon]`, `[Blocked]`.
export type ListItem = { c: Inline[]; sub: Block | null; tag?: string };
export type Align = "left" | "center" | "right" | null;
export type Tone = "up" | "down" | "watch" | null;
export type Stat = { label: string; value: string; tone: Tone };

export type Block =
  | { t: "heading"; level: 1 | 2 | 3 | 4; c: Inline[] }
  | { t: "p"; c: Inline[] }
  | { t: "list"; ordered: boolean; start: number; items: ListItem[] }
  | { t: "table"; align: Align[]; head: Inline[][]; rows: Inline[][][] }
  | { t: "quote"; c: Inline[] }
  | { t: "code"; v: string }
  | { t: "stats"; items: Stat[] }
  | { t: "hr" };

const HEADING = /^(#{1,6})\s+(.*?)\s*#*\s*$/;
const HR = /^ {0,3}([-*_])(\s*\1){2,}\s*$/;
const BULLET = /^(\s*)([-*+•])\s+(.*)$/;
const NUMBERED = /^(\s*)(\d{1,9})[.)]\s+(.*)$/;
const FENCE = /^\s*(```|~~~)\s*([A-Za-z0-9]*)/;
// `[Mon] words`: a tag of 1 to 24 characters, then a space and some words.
// `[words](address)` is a link, which keeps its words instead.
const TAG = /^\[([^\[\]\n]{1,24})\][ \t]+(\S[^]*)$/;
const QUOTE = /^\s*>\s?(.*)$/;
const DIVIDER_CELL = /^\s*:?-{1,}:?\s*$/;

// ───────────────────────────── Blocks ─────────────────────────────

export function parseMarkdown(source: string): Block[] {
  const lines = source.replace(/\r\n?/g, "\n").split("\n");
  const blocks: Block[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      i++;
      continue;
    }

    const fence = FENCE.exec(line);
    if (fence) {
      const body: string[] = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith(fence[1])) body.push(lines[i++]);
      i++; // the closing fence, if it has arrived
      if (fence[2].toLowerCase() === "stats") blocks.push({ t: "stats", items: body.map(stat).filter((s): s is Stat => s !== null) });
      else blocks.push({ t: "code", v: body.join("\n") });
      continue;
    }

    const heading = HEADING.exec(line);
    if (heading) {
      blocks.push({ t: "heading", level: Math.min(heading[1].length, 4) as 1 | 2 | 3 | 4, c: parseInline(heading[2]) });
      i++;
      continue;
    }

    if (HR.test(line)) {
      blocks.push({ t: "hr" });
      i++;
      continue;
    }

    if (isTableStart(lines, i)) {
      const head = splitRow(lines[i]);
      const align = splitRow(lines[i + 1]).map(alignOf);
      const rows: Inline[][][] = [];
      i += 2;
      while (i < lines.length && lines[i].includes("|") && lines[i].trim()) {
        const cells = splitRow(lines[i]);
        // Every row as wide as the header: short rows padded, long ones cut.
        rows.push(head.map((_, k) => parseInline(cells[k] ?? "")));
        i++;
      }
      blocks.push({ t: "table", align: head.map((_, k) => align[k] ?? null), head: head.map(parseInline), rows });
      continue;
    }

    if (QUOTE.test(line)) {
      const body: string[] = [];
      for (let q = QUOTE.exec(line); q; q = i < lines.length ? QUOTE.exec(lines[i]) : null) {
        body.push(q[1]);
        i++;
      }
      blocks.push({ t: "quote", c: parseInline(body.join("\n")) });
      continue;
    }

    if (BULLET.test(line) || NUMBERED.test(line)) {
      const end = listEnd(lines, i);
      blocks.push(parseList(lines.slice(i, end)));
      i = end;
      continue;
    }

    // A paragraph: lines up to a blank one or the start of another block.
    const body: string[] = [line.trim()];
    i++;
    while (i < lines.length && lines[i].trim() && !startsBlock(lines, i)) body.push(lines[i++].trim());
    blocks.push({ t: "p", c: parseInline(body.join("\n")) });
  }
  return blocks;
}

function startsBlock(lines: string[], i: number): boolean {
  const line = lines[i];
  return (
    FENCE.test(line) || HEADING.test(line) || HR.test(line) || QUOTE.test(line) ||
    BULLET.test(line) || NUMBERED.test(line) || isTableStart(lines, i)
  );
}

// ───────────────────────────── Stats ─────────────────────────────

// `Open edits | 5 | watch`: a label and a value, and a tone when the third
// cell names one. A line with no pipe isn't a stat.
function stat(line: string): Stat | null {
  const parts = line.split("|").map((p) => p.trim());
  if (parts.length < 2 || !parts[0] || !parts[1]) return null;
  const tone = (parts[2] ?? "").toLowerCase();
  return { label: parts[0], value: parts[1], tone: tone === "up" || tone === "down" || tone === "watch" ? tone : null };
}

// ───────────────────────────── Tables ─────────────────────────────

function isTableStart(lines: string[], i: number): boolean {
  if (i + 1 >= lines.length || !lines[i].includes("|")) return false;
  const divider = lines[i + 1];
  if (!divider.includes("-")) return false;
  const cells = splitRow(divider);
  return cells.length > 0 && cells.every((c) => DIVIDER_CELL.test(c)) && splitRow(lines[i]).length > 0;
}

// The cells of `| a | b |` (or `a | b`), with escaped pipes kept as text.
function splitRow(line: string): string[] {
  let row = line.trim();
  if (row.startsWith("|")) row = row.slice(1);
  if (row.endsWith("|") && !row.endsWith("\\|")) row = row.slice(0, -1);
  const cells: string[] = [];
  let cell = "";
  for (let k = 0; k < row.length; k++) {
    if (row[k] === "\\" && row[k + 1] === "|") {
      cell += "|";
      k++;
    } else if (row[k] === "|") {
      cells.push(cell.trim());
      cell = "";
    } else cell += row[k];
  }
  cells.push(cell.trim());
  return cells;
}

function alignOf(cell: string): Align {
  const c = cell.trim();
  const left = c.startsWith(":");
  const right = c.endsWith(":");
  return left && right ? "center" : right ? "right" : left ? "left" : null;
}

// ───────────────────────────── Lists ─────────────────────────────

type ListLine = { indent: number; ordered: boolean; n: number; text: string };

function listLine(line: string): ListLine | null {
  const b = BULLET.exec(line);
  if (b) return { indent: width(b[1]), ordered: false, n: 0, text: b[3] };
  const o = NUMBERED.exec(line);
  if (o) return { indent: width(o[1]), ordered: true, n: Number(o[2]), text: o[3] };
  return null;
}

const width = (space: string) => space.replace(/\t/g, "    ").length;

// Where the list starting at `start` ends: its items, the lines that carry
// an item on (indented, or not starting anything else), and single blank
// lines between items. Bullets turning into numbers (or back) at the list's
// own depth start a new list.
function listEnd(lines: string[], start: number): number {
  const first = listLine(lines[start])!;
  const sameList = (l: ListLine | null) => !!l && (l.indent > first.indent || l.ordered === first.ordered);
  let i = start + 1;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      if (i + 1 < lines.length && sameList(listLine(lines[i + 1]))) {
        i++;
        continue;
      }
      break;
    }
    const item = listLine(line);
    if (item && !sameList(item)) break;
    if (item || (/^\s/.test(line) && !FENCE.test(line))) {
      i++;
      continue;
    }
    if (startsBlock(lines, i)) break;
    i++; // a wrapped line of the item above
  }
  return i;
}

function parseList(lines: string[]): Block {
  const entries: ListLine[] = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    const item = listLine(line);
    if (item) entries.push(item);
    else if (entries.length) entries[entries.length - 1].text += "\n" + line.trim();
  }
  return buildList(entries, 0, entries.length);
}

// The list of entries[from, to): items at the shallowest indent, each with
// the deeper entries after it as its sub-list.
function buildList(entries: ListLine[], from: number, to: number): Block {
  const base = Math.min(...entries.slice(from, to).map((e) => e.indent));
  const first = entries[from];
  const items: ListItem[] = [];
  let k = from;
  while (k < to) {
    const e = entries[k];
    let end = k + 1;
    while (end < to && entries[end].indent > base) end++;
    const tag = TAG.exec(e.text);
    const text = tag ? tag[2] : e.text;
    const item: ListItem = { c: parseInline(text), sub: end > k + 1 ? buildList(entries, k + 1, end) : null };
    if (tag && tag[1].trim()) item.tag = tag[1].trim();
    items.push(item);
    k = end;
  }
  return { t: "list", ordered: first.ordered, start: first.ordered ? first.n : 1, items };
}

// ───────────────────────────── Inline ─────────────────────────────

const isSpace = (ch: string | undefined) => ch === undefined || /\s/.test(ch);
const isWord = (ch: string | undefined) => ch !== undefined && /[\p{L}\p{N}]/u.test(ch);

export function parseInline(text: string): Inline[] {
  const out: Inline[] = [];
  let buf = "";
  const flush = () => {
    if (buf) out.push({ t: "text", v: buf });
    buf = "";
  };

  let i = 0;
  while (i < text.length) {
    const ch = text[i];

    if (ch === "\\" && i + 1 < text.length && /[\\`*_~[\]()#|>-]/.test(text[i + 1])) {
      buf += text[i + 1];
      i += 2;
      continue;
    }

    if (ch === "\n") {
      flush();
      out.push({ t: "br" });
      i++;
      continue;
    }

    if (ch === "`") {
      const close = text.indexOf("`", i + 1);
      if (close > i + 1) {
        flush();
        out.push({ t: "code", v: text.slice(i + 1, close) });
        i = close + 1;
        continue;
      }
    }

    // [words](address): the words only.
    if (ch === "[") {
      const m = /^\[([^\]\n]+)\]\(([^)\s]*)\)/.exec(text.slice(i));
      if (m) {
        buf += m[1];
        i += m[0].length;
        continue;
      }
    }

    const span = emphasis(text, i);
    if (span) {
      flush();
      out.push({ t: span.t, c: parseInline(span.inner) });
      i = span.end;
      continue;
    }

    buf += ch;
    i++;
  }
  flush();
  return out;
}

// The emphasis opening at `i`, if one does: its kind, what it wraps and
// where it ends. A ** or ~~ never closed (the reply is still arriving) runs
// to the end of the line; a lone * or _ that never closes is just a
// character.
function emphasis(text: string, i: number): { t: "strong" | "em" | "del"; inner: string; end: number } | null {
  const ch = text[i];
  if (ch !== "*" && ch !== "_" && ch !== "~") return null;
  const double = text[i + 1] === ch;
  if (ch === "~" && !double) return null;
  const mark = double ? ch + ch : ch;
  const after = text[i + mark.length];
  if (isSpace(after) || after === ch) return null;
  // Underscores inside a word (snake_case) aren't emphasis.
  if (ch === "_" && isWord(text[i - 1])) return null;

  const lineEnd = text.indexOf("\n", i) === -1 ? text.length : text.indexOf("\n", i);
  let from = i + mark.length;
  for (;;) {
    const close = text.indexOf(mark, from);
    if (close === -1 || close >= lineEnd) break;
    // A single * looking for its close steps over a ** pair (bold inside).
    if (mark.length === 1 && text[close + 1] === ch) {
      from = close + 2;
      continue;
    }
    const before = text[close - 1];
    const next = text[close + mark.length];
    const closes =
      !isSpace(before) && close > i + mark.length && (mark.length === 2 || next !== ch) && !(ch === "_" && isWord(next));
    if (closes) {
      return { t: ch === "~" ? "del" : double ? "strong" : "em", inner: text.slice(i + mark.length, close), end: close + mark.length };
    }
    from = close + 1;
  }
  if (!double) return null;
  return { t: ch === "~" ? "del" : "strong", inner: text.slice(i + 2, lineEnd), end: lineEnd };
}

// ───────────────────────────── Lead ─────────────────────────────

// An item's bold name and what follows it, so it can be set on its own line:
// `**Armra proposal** — due Monday` → lead "Armra proposal", detail "due
// Monday". The name must open the item and be followed by a dash (—, – or -)
// or a colon, or end in a colon itself (`**Due:** Monday`). Anything else is
// { lead: c, detail: null }. McFlyKit's Markdown.lead does the same.
export function splitLead(c: Inline[]): { lead: Inline[]; detail: Inline[] | null } {
  const [first, next, ...rest] = c;
  if (first?.t !== "strong" || !first.c.length) return { lead: c, detail: null };
  if (first.c.some((n) => n.t === "br")) return { lead: c, detail: null };
  const name = trimColon(first.c);
  const after = next?.t === "text" ? /^\s*[—–:-]\s*/.exec(next.v) : null;
  if (!after && !name.colon) return { lead: c, detail: null };
  const head = next?.t === "text" ? next.v.slice(after ? after[0].length : 0).replace(/^\s+/, "") : null;
  const detail: Inline[] = [...(head ? [{ t: "text" as const, v: head }] : []), ...(next && next.t !== "text" ? [next] : []), ...rest];
  return { lead: name.c, detail: detail.length ? detail : null };
}

// The name without a colon at its end (`Due Monday:`), and whether it had one.
function trimColon(c: Inline[]): { c: Inline[]; colon: boolean } {
  const last = c[c.length - 1];
  if (last?.t !== "text" || !/:\s*$/.test(last.v)) return { c, colon: false };
  const v = last.v.replace(/:\s*$/, "");
  return { c: v ? [...c.slice(0, -1), { t: "text", v }] : c.slice(0, -1), colon: true };
}

// ───────────────────────────── Plain text ─────────────────────────────

// The answer as words alone, for reading it aloud or copying it somewhere
// that doesn't speak Markdown: list items and table rows become sentences.
export function plainText(source: string): string {
  const parts: string[] = [];
  const inline = (c: Inline[]): string =>
    c.map((n) => (n.t === "text" || n.t === "code" ? n.v : n.t === "br" ? "\n" : inline(n.c))).join("");
  const sentence = (s: string) => {
    const t = s.trim();
    return !t || /[.!?:;…]$/.test(t) ? t : `${t}.`;
  };
  const list = (b: Extract<Block, { t: "list" }>) => {
    for (const item of b.items) {
      parts.push(sentence(item.tag ? `${item.tag}: ${inline(item.c)}` : inline(item.c)));
      if (item.sub) walk([item.sub]);
    }
  };
  const walk = (blocks: Block[]) => {
    for (const b of blocks) {
      if (b.t === "heading") parts.push(sentence(inline(b.c)));
      else if (b.t === "p" || b.t === "quote") parts.push(inline(b.c).trim());
      else if (b.t === "list") list(b);
      else if (b.t === "table") {
        const head = b.head.map(inline);
        for (const row of b.rows) {
          const cells = row.map(inline);
          parts.push(sentence(cells.map((c, k) => (k && head[k] ? `${head[k]} ${c}` : c)).filter((c) => c.trim()).join(", ")));
        }
      } else if (b.t === "code") parts.push(b.v);
      else if (b.t === "stats") for (const s of b.items) parts.push(sentence(`${s.label} ${s.value}`));
    }
  };
  walk(parseMarkdown(source));
  return parts.filter(Boolean).join("\n");
}
