import Foundation
import XCTest
@testable import McFlyKit

/// The full-screen Ask's Markdown: the console's cases (admin/tests/markdown.test.mjs),
/// parsed to blocks, never a link, and sane while it streams.
final class MarkdownTests: XCTestCase {
    func testHeadingsParagraphsAndRules() {
        XCTAssertEqual(Markdown.blocks("### Markets\nNVDA led.\nAAPL lagged.\n\n---\n\nDone."), [
            .heading(level: 3, text: "Markets"),
            .paragraph("NVDA led.\nAAPL lagged."),
            .rule,
            .paragraph("Done."),
        ])
        // Deeper than four is shown as four; no space after # is just text; a closing run goes.
        XCTAssertEqual(Markdown.blocks("###### Small"), [.heading(level: 4, text: "Small")])
        XCTAssertEqual(Markdown.blocks("#hashtag"), [.paragraph("#hashtag")])
        XCTAssertEqual(Markdown.blocks("## Title ##\n## C#"), [.heading(level: 2, text: "Title"), .heading(level: 2, text: "C#")])
    }

    func testBulletedAndNumberedListsNestByIndent() {
        XCTAssertEqual(Markdown.blocks("- One\n  - One a\n- Two\n\n1. First\n2. Second"), [
            .list(.init(ordered: false, items: [
                .init("One", sub: .init(ordered: false, items: [.init("One a")])),
                .init("Two"),
            ])),
            .list(.init(ordered: true, items: [.init("First"), .init("Second")])),
        ])
        // A list can start anywhere, and a • works as a bullet.
        XCTAssertEqual(Markdown.blocks("3. Third"), [.list(.init(ordered: true, start: 3, items: [.init("Third")]))])
        XCTAssertEqual(Markdown.blocks("• Dot"), [.list(.init(ordered: false, items: [.init("Dot")]))])
        // A paragraph right before a list ends at the list.
        XCTAssertEqual(Markdown.blocks("Three things:\n- a"), [.paragraph("Three things:"), .list(.init(ordered: false, items: [.init("a")]))])
    }

    func testWrappedLinesStayWithTheirItemAndABlankLineKeepsOneList() {
        XCTAssertEqual(Markdown.blocks("- Alpha\n  carries on\n\n- Beta\n\nAfter."), [
            .list(.init(ordered: false, items: [.init("Alpha\ncarries on"), .init("Beta")])),
            .paragraph("After."),
        ])
    }

    func testTablesHaveAHeaderAlignmentAndRowsAsWideAsTheHeader() {
        let blocks = Markdown.blocks("| Symbol | Price | Change |\n|:--|--:|:-:|\n| NVDA | $120 | **+2.1%** |\n| AAPL | $230 |\n| X | 1 | 2 | extra |")
        XCTAssertEqual(blocks, [.table(.init(
            alignments: [.leading, .trailing, .center],
            header: ["Symbol", "Price", "Change"],
            rows: [["NVDA", "$120", "**+2.1%**"], ["AAPL", "$230", ""], ["X", "1", "2"]]))])
    }

    func testWhileStreamingATableHeaderIsAParagraphUntilItsDividerArrives() {
        XCTAssertEqual(Markdown.blocks("| Symbol | Price |"), [.paragraph("| Symbol | Price |")])
        guard case .table = Markdown.blocks("| Symbol | Price |\n|---|---|").first else { return XCTFail("expected a table") }
        // Escaped pipes are text in a cell.
        guard case .table(let table) = Markdown.blocks("a | b\n--|--\nx \\| y | z").first else { return XCTFail("expected a table") }
        XCTAssertEqual(table.rows, [["x | y", "z"]])
        XCTAssertEqual(table.alignments, [nil, nil])
    }

    func testQuotesAndFencedCodeIncludingAFenceStillOpen() {
        XCTAssertEqual(Markdown.blocks("> Heads up\n> twice\n\nok"), [.quote("Heads up\ntwice"), .paragraph("ok")])
        XCTAssertEqual(Markdown.blocks("```\n**raw**\n```\nafter"), [.code("**raw**"), .paragraph("after")])
        XCTAssertEqual(Markdown.blocks("```js\nlet a"), [.code("let a")])
    }

    func testAListItemMayOpenWithATagForAChip() {
        XCTAssertEqual(Markdown.blocks("- [Mon] **Armra proposal** — 2–3 proofs of concept\n- [Waiting] Jamie's scheduling\n- plain"), [
            .list(.init(ordered: false, items: [
                .init("**Armra proposal** — 2–3 proofs of concept", tag: "Mon"),
                .init("Jamie's scheduling", tag: "Waiting"),
                .init("plain"),
            ])),
        ])
        // Numbered items and nested ones carry tags too.
        XCTAssertEqual(Markdown.blocks("1. [Today] Ship\n   - [Done] tests"), [
            .list(.init(ordered: true, items: [.init("Ship", tag: "Today", sub: .init(ordered: false, items: [.init("tests", tag: "Done")]))])),
        ])
        // Not a tag: a link, an empty or long bracket, brackets with nothing after, or one mid-line.
        XCTAssertEqual(Markdown.splitTag("[the brief](https://x) now").tag, nil)
        XCTAssertEqual(Markdown.splitTag("[] x").tag, nil)
        XCTAssertEqual(Markdown.splitTag("[a tag that goes on and on and on] x").tag, nil)
        XCTAssertEqual(Markdown.splitTag("[Wednesday 10:30 AM] **Dentist**").tag, "Wednesday 10:30 AM")
        XCTAssertEqual(Markdown.splitTag("[Mon]").tag, nil)
        XCTAssertEqual(Markdown.splitTag("[Mon]x").tag, nil)
        XCTAssertEqual(Markdown.splitTag("see [Mon] x").tag, nil)
        XCTAssertEqual(Markdown.splitTag("[Due Mon 3 PM]  Armra").tag, "Due Mon 3 PM")
        XCTAssertEqual(Markdown.splitTag("[Due Mon 3 PM]  Armra").text, "Armra")
    }

    func testAnItemsBoldNameSplitsFromItsDetail() {
        XCTAssertTrue(Markdown.lead("**Armra proposal** — due Monday, Todd wants 2–3 proofs") == ("Armra proposal", "due Monday, Todd wants 2–3 proofs"))
        XCTAssertTrue(Markdown.lead("**J442 Ashley Henson** – fix the sound") == ("J442 Ashley Henson", "fix the sound"))
        XCTAssertTrue(Markdown.lead("**Runway**: waiting on Jamie") == ("Runway", "waiting on Jamie"))
        XCTAssertTrue(Markdown.lead("**Due Monday:** the proposal") == ("Due Monday", "the proposal"))
        XCTAssertTrue(Markdown.lead("**Homestead** — ") == ("Homestead", nil))
        // Not a lead: no bold first, bold mid-sentence, bold with nothing to split on, or one still arriving.
        for text in ["Standup at 9", "Call **Sophie** — today", "**NVDA** is up 2%", "**Armra propo", "**a\nb** — c"] {
            XCTAssertTrue(Markdown.lead(text) == (text, nil), text)
        }
    }

    func testAStatsFenceIsTilesNotCode() {
        XCTAssertEqual(Markdown.blocks("```stats\nOpen edits | 5\nDue Monday | 1 | watch\nPortfolio | $118.4k | up\nno pipe here\n| 3\n```\nafter"), [
            .stats([
                .init(label: "Open edits", value: "5"),
                .init(label: "Due Monday", value: "1", tone: .watch),
                .init(label: "Portfolio", value: "$118.4k", tone: .up),
            ]),
            .paragraph("after"),
        ])
        // An unknown tone is no tone; the fence's word is read however it's cased; other fences stay code.
        XCTAssertEqual(Markdown.blocks("```Stats\nA | 1 | loud"), [.stats([.init(label: "A", value: "1")])])
        XCTAssertEqual(Markdown.blocks("```json\nA | 1"), [.code("A | 1")])
        // While streaming, an open stats fence shows what has arrived.
        XCTAssertEqual(Markdown.blocks("```stats\nOpen edits | 5\nDue Mon"), [.stats([.init(label: "Open edits", value: "5")])])
    }

    func testEveryPrefixOfAnAnswerParses() {
        let answer = "### Today\nYou have **three** things.\n\n```stats\nOpen | 3 | watch\n```\n\n- [9:00] **Standup**\n  - room 2\n1. Ship\n\n| A | B |\n|---|--:|\n| x | *1* |\n\n> note\n\n```\ncode\n```\n\n---\n## Done ##"
        var prefix = ""
        for ch in answer {
            prefix.append(ch)
            for block in Markdown.blocks(prefix) {
                if case .table(let table) = block { XCTAssertTrue(table.rows.allSatisfy { $0.count == table.header.count }) }
            }
            _ = Markdown.inline(prefix)
        }
        // Bullets turning into numbers at the same depth start a new list.
        XCTAssertEqual(Markdown.blocks(answer).map(kind), ["heading", "paragraph", "stats", "list", "list", "table", "quote", "code", "rule", "heading"])
    }

    private func kind(_ block: Markdown.Block) -> String {
        switch block {
        case .heading: return "heading"
        case .paragraph: return "paragraph"
        case .list: return "list"
        case .table: return "table"
        case .quote: return "quote"
        case .code: return "code"
        case .stats: return "stats"
        case .rule: return "rule"
        }
    }

    // MARK: Inline

    func testBoldItalicStruckAndCode() {
        let styled = Markdown.inline("**NVDA** is up *2.1%* (`$120`), ~~flat~~")
        XCTAssertEqual(String(styled.characters), "NVDA is up 2.1% ($120), flat")
        XCTAssertEqual(intent(of: "NVDA", in: styled), .stronglyEmphasized)
        XCTAssertEqual(intent(of: "2.1%", in: styled), .emphasized)
        XCTAssertEqual(intent(of: "$120", in: styled), .code)
        XCTAssertEqual(intent(of: "flat", in: styled), .strikethrough)
        // Line breaks stay.
        XCTAssertEqual(String(Markdown.inline("a\nb").characters), "a\nb")
    }

    func testAsterisksAndUnderscoresThatArentEmphasisStay() {
        XCTAssertEqual(String(Markdown.inline("2 * 3 * 4").characters), "2 * 3 * 4")
        XCTAssertEqual(String(Markdown.inline("snake_case_name and a_b").characters), "snake_case_name and a_b")
        XCTAssertEqual(String(Markdown.inline("\\*not em\\*").characters), "*not em*")
    }

    func testWhileStreamingAnUnclosedBoldIsBoldToTheEndOfItsLine() {
        XCTAssertEqual(Markdown.closingOpenBold("Revenue **up 4"), "Revenue **up 4**")
        XCTAssertEqual(Markdown.closingOpenBold("**open  \nnext"), "**open**  \nnext")
        XCTAssertEqual(intent(of: "up 4", in: Markdown.inline("Revenue **up 4")), .stronglyEmphasized)
        // A trailing pair with nothing after it yet stays as it is; closed pairs and code are left alone.
        XCTAssertEqual(Markdown.closingOpenBold("Revenue **"), "Revenue **")
        XCTAssertEqual(Markdown.closingOpenBold("**a** and **b**"), "**a** and **b**")
        XCTAssertEqual(Markdown.closingOpenBold("`a**b` c"), "`a**b` c")
    }

    func testLinksKeepTheirWordsNeverTheirAddress() {
        for source in ["see [the brief](https://evil.example/x) now", "auto <https://evil.example/x> and https://bare.example/y",
                       "![a chart](https://evil.example/c.png) after", "**[bold link](https://evil.example)**"] {
            let styled = Markdown.inline(source)
            XCTAssertTrue(styled.runs.allSatisfy { $0.link == nil && $0.imageURL == nil }, source)
        }
        XCTAssertEqual(String(Markdown.inline("see [the brief](https://evil.example/x) now").characters), "see the brief now")
        XCTAssertEqual(String(Markdown.inline("![a chart](https://evil.example/c.png) after").characters), "a chart after")
        XCTAssertEqual(intent(of: "bold link", in: Markdown.inline("**[bold link](https://evil.example)**")), .stronglyEmphasized)
    }

    func testTagsAreText() {
        let styled = Markdown.inline("<img src=x onerror=\"alert(1)\"> **hi**")
        XCTAssertEqual(String(styled.characters), "<img src=x onerror=\"alert(1)\"> hi")
        XCTAssertNil(intent(of: "<img", in: styled))
        XCTAssertEqual(intent(of: "hi", in: styled), .stronglyEmphasized)
    }

    func testReadModeIsSentAsRead() {
        XCTAssertEqual(AssistantClient.Mode.read.rawValue, "read")
    }

    func testAServerWithoutReadModeIsAskedAgainInChat() {
        let old = Data(#"{"error":"mode must be \"chat\" or \"quick\""}"#.utf8)
        XCTAssertTrue(AssistantClient.rejectsMode(status: 400, body: old))
        XCTAssertFalse(AssistantClient.rejectsMode(status: 400, body: Data(#"{"error":"message must be a non-empty string"}"#.utf8)))
        XCTAssertFalse(AssistantClient.rejectsMode(status: 500, body: old))
        XCTAssertFalse(AssistantClient.rejectsMode(status: 400, body: Data("not json".utf8)))
    }

    /// The emphasis on the run holding `words`.
    private func intent(of words: String, in styled: AttributedString) -> InlinePresentationIntent? {
        for run in styled.runs where String(styled[run.range].characters).contains(words) {
            return run.inlinePresentationIntent
        }
        XCTFail("\(words) isn't in \(String(styled.characters))")
        return nil
    }
}
