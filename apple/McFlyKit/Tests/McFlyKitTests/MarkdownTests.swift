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

    func testEveryPrefixOfAnAnswerParses() {
        let answer = "### Today\nYou have **three** things.\n\n- **9:00** Standup\n  - room 2\n1. Ship\n\n| A | B |\n|---|--:|\n| x | *1* |\n\n> note\n\n```\ncode\n```\n\n---\n## Done ##"
        var prefix = ""
        for ch in answer {
            prefix.append(ch)
            for block in Markdown.blocks(prefix) {
                if case .table(let table) = block { XCTAssertTrue(table.rows.allSatisfy { $0.count == table.header.count }) }
            }
            _ = Markdown.inline(prefix)
        }
        // Bullets turning into numbers at the same depth start a new list.
        XCTAssertEqual(Markdown.blocks(answer).map(kind), ["heading", "paragraph", "list", "list", "table", "quote", "code", "rule", "heading"])
    }

    private func kind(_ block: Markdown.Block) -> String {
        switch block {
        case .heading: return "heading"
        case .paragraph: return "paragraph"
        case .list: return "list"
        case .table: return "table"
        case .quote: return "quote"
        case .code: return "code"
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
