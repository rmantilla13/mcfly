import Foundation

/// The Markdown the assistant writes in `read` mode (the full-screen Ask),
/// as blocks a view can lay out: the console's `admin/lib/markdown.ts`, the
/// same rules. Headings, paragraphs, bulleted and numbered lists (nested by
/// indent), tables, quotes, rules and fenced code; a block's words stay
/// Markdown source for `inline(_:)` to style.
///
/// Two shapes are the assistant's own (its `layout` skill, docs/ASSISTANT.md):
/// a list item opening with `[Mon]` or `[Blocked]` carries that as its `tag`
/// (a chip), and a fence marked `stats` is a `.stats` block of label | value
/// | tone lines (tiles), not code.
///
/// It is fed a reply while it streams, so half of anything is fine: a table's
/// header is a paragraph until its divider row arrives, an open fence runs to
/// the end, an unclosed `**` is bold to the end of its line.
public enum Markdown {
    public enum Alignment: Equatable, Sendable { case leading, center, trailing }

    public struct List: Equatable, Sendable {
        public var ordered: Bool
        /// The first item's number; 1 for bullets.
        public var start: Int
        public var items: [ListItem]

        public init(ordered: Bool, start: Int = 1, items: [ListItem]) {
            self.ordered = ordered
            self.start = start
            self.items = items
        }
    }

    public struct ListItem: Equatable, Sendable {
        public var text: String
        /// `[Mon]`, `[Blocked]`: the bracketed word or two the item opened
        /// with, taken off `text`. One to 24 characters, no link after it.
        public var tag: String?
        public var sub: List?

        public init(_ text: String, tag: String? = nil, sub: List? = nil) {
            self.text = text
            self.tag = tag
            self.sub = sub
        }
    }

    /// A key figure in a stats block.
    public struct Stat: Equatable, Sendable {
        public enum Tone: String, Equatable, Sendable { case up, down, watch }

        public var label: String
        public var value: String
        public var tone: Tone?

        public init(label: String, value: String, tone: Tone? = nil) {
            self.label = label
            self.value = value
            self.tone = tone
        }
    }

    public struct Table: Equatable, Sendable {
        /// One per column; nil when the divider doesn't say.
        public var alignments: [Alignment?]
        public var header: [String]
        /// Every row as wide as the header: short rows padded, long ones cut.
        public var rows: [[String]]

        public init(alignments: [Alignment?], header: [String], rows: [[String]]) {
            self.alignments = alignments
            self.header = header
            self.rows = rows
        }
    }

    public enum Block: Equatable, Sendable {
        /// 1 to 4; deeper headings read as 4.
        case heading(level: Int, text: String)
        /// Its lines joined by "\n", kept as line breaks.
        case paragraph(String)
        case list(List)
        case table(Table)
        case quote(String)
        case code(String)
        /// A ```stats fence: its `label | value | tone` lines, lines without a
        /// pipe (or still arriving) left out.
        case stats([Stat])
        case rule
    }

    // MARK: Blocks

    public static func blocks(_ source: String) -> [Block] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            if isBlank(line) {
                i += 1
                continue
            }

            if let fence = fence(line) {
                var body: [String] = []
                i += 1
                while i < lines.count && !trimmed(lines[i]).hasPrefix(fence) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1  // the closing fence, if it has arrived
                blocks.append(fenceInfo(line) == "stats" ? .stats(body.compactMap(stat)) : .code(body.joined(separator: "\n")))
                continue
            }

            if let heading = heading(line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            if isRule(line) {
                blocks.append(.rule)
                i += 1
                continue
            }

            if isTableStart(lines, i) {
                let header = cells(lines[i])
                let alignments = cells(lines[i + 1]).map(alignment)
                var rows: [[String]] = []
                i += 2
                while i < lines.count && lines[i].contains("|") && !isBlank(lines[i]) {
                    let row = cells(lines[i])
                    rows.append(header.indices.map { $0 < row.count ? row[$0] : "" })
                    i += 1
                }
                blocks.append(.table(Table(alignments: header.indices.map { $0 < alignments.count ? alignments[$0] : nil },
                                           header: header, rows: rows)))
                continue
            }

            if quoted(line) != nil {
                var body: [String] = []
                while i < lines.count, let text = quoted(lines[i]) {
                    body.append(text)
                    i += 1
                }
                blocks.append(.quote(body.joined(separator: "\n")))
                continue
            }

            if listLine(line) != nil {
                let end = listEnd(lines, i)
                blocks.append(.list(parseList(Array(lines[i..<end]))))
                i = end
                continue
            }

            // A paragraph: lines up to a blank one or the start of another block.
            var body = [trimmed(line)]
            i += 1
            while i < lines.count && !isBlank(lines[i]) && !startsBlock(lines, i) {
                body.append(trimmed(lines[i]))
                i += 1
            }
            blocks.append(.paragraph(body.joined(separator: "\n")))
        }
        return blocks
    }

    private static func startsBlock(_ lines: [String], _ i: Int) -> Bool {
        let line = lines[i]
        return fence(line) != nil || heading(line) != nil || isRule(line) || quoted(line) != nil
            || listLine(line) != nil || isTableStart(lines, i)
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
    private static func isBlank(_ s: String) -> Bool { s.allSatisfy(\.isWhitespace) }

    /// "```" or "~~~" when the line opens (or closes) a fence.
    private static func fence(_ line: String) -> String? {
        let t = line.drop(while: \.isWhitespace)
        if t.hasPrefix("```") { return "```" }
        if t.hasPrefix("~~~") { return "~~~" }
        return nil
    }

    /// The word after an opening fence (` ```stats `), lower-cased; "" without one.
    private static func fenceInfo(_ line: String) -> String {
        let t = line.drop(while: \.isWhitespace).dropFirst(3)
        return String(t.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
    }

    // MARK: Stats

    /// `Open edits | 5 | watch`: a label and a value, and a tone when the
    /// third cell names one. A line with no pipe isn't a stat.
    static func stat(_ line: String) -> Stat? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map { trimmed(String($0)) }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return Stat(label: parts[0], value: parts[1], tone: parts.count > 2 ? Stat.Tone(rawValue: parts[2].lowercased()) : nil)
    }

    /// `## Title`: one to six #s, then a space. A closing run of #s goes.
    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard let first = rest.first, first.isWhitespace else { return nil }
        var text = trimmed(String(rest))
        let closing = text.reversed().prefix(while: { $0 == "#" }).count
        if closing > 0 {
            let kept = text.dropLast(closing)
            if kept.isEmpty || kept.last!.isWhitespace { text = trimmed(String(kept)) }
        }
        return (min(hashes, 4), text)
    }

    /// `---`, `***` or `___`, three or more, spaces allowed between.
    private static func isRule(_ line: String) -> Bool {
        let indent = line.prefix(while: { $0 == " " }).count
        guard indent <= 3 else { return false }
        let rest = line.dropFirst(indent)
        guard let mark = rest.first, "-*_".contains(mark) else { return false }
        var count = 0
        for ch in rest {
            if ch == mark { count += 1 } else if !ch.isWhitespace { return false }
        }
        return count >= 3
    }

    /// A quote line's text, after the `>` and one space.
    private static func quoted(_ line: String) -> String? {
        let t = line.drop(while: \.isWhitespace)
        guard t.first == ">" else { return nil }
        var rest = t.dropFirst()
        if rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        return String(rest)
    }

    // MARK: Tables

    private static func isTableStart(_ lines: [String], _ i: Int) -> Bool {
        guard i + 1 < lines.count, lines[i].contains("|") else { return false }
        let divider = lines[i + 1]
        guard divider.contains("-") else { return false }
        let parts = cells(divider)
        return !parts.isEmpty && parts.allSatisfy(isDividerCell)
    }

    private static func isDividerCell(_ cell: String) -> Bool {
        var c = Substring(trimmed(cell))
        if c.first == ":" { c = c.dropFirst() }
        if c.last == ":" { c = c.dropLast() }
        return !c.isEmpty && c.allSatisfy { $0 == "-" }
    }

    /// The cells of `| a | b |` (or `a | b`), an escaped pipe kept as text.
    static func cells(_ line: String) -> [String] {
        var row = Substring(trimmed(line))
        if row.first == "|" { row = row.dropFirst() }
        if row.last == "|" && !row.hasSuffix("\\|") { row = row.dropLast() }
        var cells: [String] = []
        var cell = ""
        var chars = row.makeIterator()
        var pending: Character? = chars.next()
        while let ch = pending {
            pending = chars.next()
            if ch == "\\" && pending == "|" {
                cell.append("|")
                pending = chars.next()
            } else if ch == "|" {
                cells.append(trimmed(cell))
                cell = ""
            } else {
                cell.append(ch)
            }
        }
        cells.append(trimmed(cell))
        return cells
    }

    private static func alignment(_ cell: String) -> Alignment? {
        let c = trimmed(cell)
        switch (c.hasPrefix(":"), c.hasSuffix(":")) {
        case (true, true): return .center
        case (false, true): return .trailing
        case (true, false): return .leading
        case (false, false): return nil
        }
    }

    // MARK: Lists

    private struct Entry {
        var indent: Int
        var ordered: Bool
        var number: Int
        var text: String
    }

    /// `- item`, `* item`, `+ item`, `• item`, `1. item` or `1) item`.
    private static func listLine(_ line: String) -> Entry? {
        let space = line.prefix(while: \.isWhitespace)
        let indent = space.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let rest = line.dropFirst(space.count)
        func text(after marker: Int) -> String? {
            let after = rest.dropFirst(marker)
            guard let first = after.first, first.isWhitespace else { return nil }
            return String(after.drop(while: \.isWhitespace))
        }
        if let mark = rest.first, "-*+•".contains(mark), let text = text(after: 1) {
            return Entry(indent: indent, ordered: false, number: 0, text: text)
        }
        let digits = rest.prefix(while: \.isASCIIDigit)
        if (1...9).contains(digits.count), let mark = rest.dropFirst(digits.count).first, mark == "." || mark == ")",
           let text = text(after: digits.count + 1) {
            return Entry(indent: indent, ordered: true, number: Int(digits) ?? 1, text: text)
        }
        return nil
    }

    /// Where the list starting at `start` ends: its items, the lines that
    /// carry an item on (indented, or not starting anything else), and single
    /// blank lines between items. Bullets turning into numbers (or back) at
    /// the list's own depth start a new list.
    private static func listEnd(_ lines: [String], _ start: Int) -> Int {
        let first = listLine(lines[start])!
        func sameList(_ entry: Entry?) -> Bool {
            guard let entry else { return false }
            return entry.indent > first.indent || entry.ordered == first.ordered
        }
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            if isBlank(line) {
                if i + 1 < lines.count && sameList(listLine(lines[i + 1])) {
                    i += 1
                    continue
                }
                break
            }
            let item = listLine(line)
            if item != nil && !sameList(item) { break }
            if item != nil || (line.first?.isWhitespace == true && fence(line) == nil) {
                i += 1
                continue
            }
            if startsBlock(lines, i) { break }
            i += 1  // a wrapped line of the item above
        }
        return i
    }

    private static func parseList(_ lines: [String]) -> List {
        var entries: [Entry] = []
        for line in lines where !isBlank(line) {
            if let entry = listLine(line) {
                entries.append(entry)
            } else if !entries.isEmpty {
                entries[entries.count - 1].text += "\n" + trimmed(line)
            }
        }
        return buildList(entries, entries.indices)
    }

    /// The items at the shallowest indent, each with the deeper entries after
    /// it as its sub-list.
    private static func buildList(_ entries: [Entry], _ range: Range<Int>) -> List {
        let base = entries[range].map(\.indent).min() ?? 0
        let first = entries[range.lowerBound]
        var items: [ListItem] = []
        var k = range.lowerBound
        while k < range.upperBound {
            var end = k + 1
            while end < range.upperBound && entries[end].indent > base { end += 1 }
            let (tag, text) = splitTag(entries[k].text)
            items.append(ListItem(text, tag: tag, sub: end > k + 1 ? buildList(entries, (k + 1)..<end) : nil))
            k = end
        }
        return List(ordered: first.ordered, start: first.ordered ? first.number : 1, items: items)
    }

    /// `[Mon] Armra proposal` → ("Mon", "Armra proposal"). The tag is 1 to 24
    /// characters, none of them a bracket or a newline, followed by a space
    /// and some words; `[words](address)` is a link, which keeps its words.
    static func splitTag(_ text: String) -> (tag: String?, text: String) {
        guard text.first == "[", let close = text.firstIndex(of: "]") else { return (nil, text) }
        let tag = String(text[text.index(after: text.startIndex)..<close])
        guard (1...24).contains(tag.count), !tag.contains("["), !tag.contains("\n"), !tag.allSatisfy(\.isWhitespace) else { return (nil, text) }
        let after = text[text.index(after: close)...]
        guard let first = after.first, first == " " || first == "\t" else { return (nil, text) }
        let rest = String(after.drop(while: { $0 == " " || $0 == "\t" }))
        guard !rest.isEmpty else { return (nil, text) }
        return (trimmed(tag), rest)
    }

    // MARK: Lead

    /// An item's bold name and what follows it, so a view can set the name
    /// on its own line: `**Armra proposal** — due Monday` → ("Armra
    /// proposal", "due Monday"). The name must open the item and be followed
    /// by a dash (—, – or -) or a colon, or end in a colon itself
    /// (`**Due:** Monday`). Anything else, or a name still arriving, is
    /// (text, nil).
    public static func lead(_ text: String) -> (lead: String, detail: String?) {
        guard text.hasPrefix("**") else { return (text, nil) }
        let body = text.dropFirst(2)
        guard let close = body.range(of: "**") else { return (text, nil) }
        var name = String(body[..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        var rest = body[close.upperBound...].drop(while: { $0 == " " })
        guard !name.isEmpty, !name.contains("\n") else { return (text, nil) }
        if let mark = rest.first, "—–-:".contains(mark) {
            rest = rest.dropFirst()
        } else if name.hasSuffix(":") {
            name.removeLast()
        } else {
            return (text, nil)
        }
        if name.hasSuffix(":") { name.removeLast() }
        let detail = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return (name, nil) }
        return (name.trimmingCharacters(in: .whitespaces), detail)
    }

    // MARK: Inline

    /// A block's words, styled: bold, italic, struck and code from the
    /// Markdown, line breaks kept. Never a link: what the assistant says comes
    /// from what agents push, so a link keeps its words and loses its address,
    /// an image keeps its alt text, and a tag stays as plain text.
    public static func inline(_ text: String) -> AttributedString {
        let source = closingOpenBold(text)
        guard let styled = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return AttributedString(text) }
        // Rebuilt run by run: the words and their emphasis, nothing else.
        var clean = AttributedString()
        for run in styled.runs {
            var piece = AttributedString(styled[run.range].characters)
            if var intent = run.inlinePresentationIntent {
                intent.remove(.inlineHTML)
                if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            }
            clean.append(piece)
        }
        return clean
    }

    /// While a reply streams, a `**` with words after it is bold to the end
    /// of its line rather than two stray asterisks. One with nothing after it
    /// yet stays as it is.
    static func closingOpenBold(_ text: String) -> String {
        guard text.contains("**") else { return text }
        return text.components(separatedBy: "\n").map { line -> String in
            // Pairs outside `code`; an odd count leaves the last one open.
            var count = 0
            var lastOpen: String.Index?
            var inCode = false
            var i = line.startIndex
            while i < line.endIndex {
                if line[i] == "`" {
                    inCode.toggle()
                } else if !inCode, line[i...].hasPrefix("**") {
                    count += 1
                    lastOpen = i
                    i = line.index(i, offsetBy: 2)
                    continue
                }
                i = line.index(after: i)
            }
            guard count % 2 == 1, let open = lastOpen else { return line }
            let after = line[line.index(open, offsetBy: 2)...]
            guard let first = after.first, !first.isWhitespace, first != "*" else { return line }
            let end = line.lastIndex(where: { !$0.isWhitespace }).map { line.index(after: $0) } ?? line.endIndex
            return String(line[..<end]) + "**" + String(line[end...])
        }.joined(separator: "\n")
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
