import Foundation

/// Cuts a streaming answer into sentences as it arrives, so speech can start
/// before the model has finished. The tail that isn't a whole sentence yet is
/// returned as `rest`, to be fed back with the next delta.
public enum SpokenText {
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "'", ")", "”", "’", "]"]

    /// Whole sentences in `text`, and what's left over. With `final`, the
    /// leftover is returned as a sentence too, even without a full stop.
    public static func split(_ text: String, final: Bool) -> (sentences: [String], rest: String) {
        var sentences: [String] = []
        var current = ""
        var chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if c == "\n" {
                // A line break ends a spoken unit (a list item, a heading).
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            } else if terminators.contains(c) {
                // "3.5" or "e.g." aren't ends: a terminator must be followed by
                // whitespace (or a closing quote, then whitespace).
                var j = i + 1
                while j < chars.count, closers.contains(chars[j]) {
                    current.append(chars[j])
                    j += 1
                }
                if j < chars.count, chars[j].isWhitespace {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, !looksLikeAbbreviation(trimmed) {
                        sentences.append(trimmed)
                        current = ""
                    }
                }
                i = j - 1
            }
            i += 1
        }
        chars.removeAll()
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if final, !rest.isEmpty {
            sentences.append(rest)
            return (sentences, "")
        }
        return (sentences, final ? "" : current)
    }

    /// Markdown bits the model may still send in `quick` mode, stripped so they aren't read aloud.
    public static func plain(_ text: String) -> String {
        var out = text
        for mark in ["**", "__", "`", "#"] { out = out.replacingOccurrences(of: mark, with: "") }
        return out
    }

    private static let titles: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "st", "vs", "inc", "no", "jr", "sr"]

    private static func looksLikeAbbreviation(_ sentence: String) -> Bool {
        guard let last = sentence.split(separator: " ").last, last.hasSuffix(".") else { return false }
        let word = String(last).trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’()[]"))
        // Dotted initials ("U.S.", "e.g.") and titles ("Dr.") don't end a sentence.
        if word.range(of: #"^(?:[A-Za-z]\.)+$"#, options: .regularExpression) != nil { return true }
        return titles.contains(String(word.dropLast()).lowercased())
    }
}
