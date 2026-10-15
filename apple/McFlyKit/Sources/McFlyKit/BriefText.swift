import Foundation

/// A brief's body is plain text: paragraphs separated by blank lines, and
/// lines starting with `- ` are bullets. This turns it into blocks a view can
/// lay out with real bullets and spacing.
public enum BriefBlock: Equatable, Sendable {
    case paragraph(String)
    case bullets([String])
}

public enum BriefText {
    public static func blocks(_ body: String) -> [BriefBlock] {
        var blocks: [BriefBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushBullets() {
            if !bullets.isEmpty {
                blocks.append(.bullets(bullets))
                bullets = []
            }
        }

        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushBullets()
            } else if let bullet = bulletText(line) {
                flushParagraph()
                bullets.append(bullet)
            } else if !bullets.isEmpty {
                // A wrapped continuation of the bullet above.
                bullets[bullets.count - 1] += " " + line
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        flushBullets()
        return blocks
    }

    /// The first paragraph, for a one-line preview.
    public static func summary(_ body: String) -> String {
        for block in blocks(body) {
            switch block {
            case .paragraph(let text): return text
            case .bullets(let items): if let first = items.first { return first }
            }
        }
        return ""
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "• ", "* "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
