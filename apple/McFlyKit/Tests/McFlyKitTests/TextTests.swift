import XCTest
@testable import McFlyKit

final class TextTests: XCTestCase {
    func testBriefBodyBecomesParagraphsAndBullets() {
        let body = "Three things for today.\n\n- The Fed minutes land at 1 PM CT; markets are pricing a hold.\n- Your 3 PM call moved to 3:30.\n- Rain clears by noon, 71° this afternoon."
        XCTAssertEqual(BriefText.blocks(body), [
            .paragraph("Three things for today."),
            .bullets(["The Fed minutes land at 1 PM CT; markets are pricing a hold.", "Your 3 PM call moved to 3:30.", "Rain clears by noon, 71° this afternoon."]),
        ])
        XCTAssertEqual(BriefText.summary(body), "Three things for today.")
    }

    func testWrappedLinesJoinAndBulletsCanFollowText() {
        let body = "Line one\nline two.\n- a\n  continued\n- b\n\nLast."
        XCTAssertEqual(BriefText.blocks(body), [
            .paragraph("Line one line two."),
            .bullets(["a continued", "b"]),
            .paragraph("Last."),
        ])
        XCTAssertEqual(BriefText.blocks(""), [])
    }

    func testSentencesSplitAsTheyStream() {
        let (sentences, rest) = SpokenText.split("AAPL is up 1.13% today. NVDA leads the Nasdaq", final: false)
        XCTAssertEqual(sentences, ["AAPL is up 1.13% today."])
        XCTAssertEqual(rest, " NVDA leads the Nasdaq")
        let (all, none) = SpokenText.split(rest + ".", final: true)
        XCTAssertEqual(all, ["NVDA leads the Nasdaq."])
        XCTAssertEqual(none, "")
    }

    func testAbbreviationsQuotesAndLinesAreHandled() {
        let (sentences, rest) = SpokenText.split("He said \"Buy.\" Then the U.S. market closed up. Dr. Brown agrees, e.g. now. Done!", final: false)
        XCTAssertEqual(sentences, ["He said \"Buy.\"", "Then the U.S. market closed up.", "Dr. Brown agrees, e.g. now."])
        XCTAssertEqual(rest, " Done!")
        let (lines, tail) = SpokenText.split("Three things\n- Fed minutes at 1 PM\n- Call moved", final: false)
        XCTAssertEqual(lines, ["Three things", "- Fed minutes at 1 PM"])
        XCTAssertEqual(tail, "- Call moved")
        XCTAssertEqual(SpokenText.plain("**Bold** `code` # heading"), "Bold code  heading")
    }

    func testFormatting() {
        XCTAssertEqual(Format.change(2.78, pct: 1.13), "+2.78 (+1.13%)")
        XCTAssertEqual(Format.change(-3.1, pct: -1.62), "−3.10 (−1.62%)")
        XCTAssertEqual(Format.change(nil, pct: 0), "(0.00%)")
        XCTAssertEqual(Format.percent(nil), "")
        let now = Date()
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-30), now: now), "Just now")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-20 * 60), now: now), "20 min ago")
        XCTAssertEqual(Format.relative(now.addingTimeInterval(-3 * 3600), now: now), "3 hr ago")
        XCTAssertEqual(Format.dayLabel(now, now: now), "Today")
        XCTAssertEqual(Format.dayLabel(now.addingTimeInterval(-86_400), now: now), "Yesterday")
        XCTAssertEqual("admin only".sentenceCased, "Admin only")
    }
}
