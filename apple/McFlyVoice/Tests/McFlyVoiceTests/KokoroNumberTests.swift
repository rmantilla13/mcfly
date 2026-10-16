import Foundation
import Testing
@testable import McFlyVoice
@testable import KokoroG2P

/// Numbers must reach the voice as words: the pronunciation model guesses at digits and
/// read "4,000" and "30:2" as "ex".
@Suite struct KokoroNumberTests {
    @Test func normalizerReadsGroupedThousandsAndPercent() {
        #expect(EnglishTextNormalizer.normalize("at most 4,000 milligrams") == "at most four thousand milligrams")
        #expect(EnglishTextNormalizer.normalize("1 to 25000, and 20% less") == "one to twenty five thousand, and twenty percent less")
        #expect(EnglishTextNormalizer.normalize("1 to 10 bleach") == "one to ten bleach")
        #expect(EnglishTextNormalizer.normalize("a 0.5 percent solution") == "a zero point five percent solution")
        // Not thousands: left for the phonemizer, which spells each digit run.
        #expect(EnglishTextNormalizer.normalize("options 1,2,3") == "options 1,2,3")
    }

    @Test func normalizerSpellsFractionCharactersSuperscriptsAndSubscripts() {
        // The phonemizer can't spell these, and used to drop them: "2½ tablets" was "two tablets".
        let spoken = { (text: String) in
            EnglishTextNormalizer.normalize(text).split(separator: " ").joined(separator: " ")
        }
        #expect(spoken("Give 2½ tablets, or 1 ¼ cups.") == "Give two and a half tablets, or one and a quarter cups.")
        #expect(spoken("area = ½ × base; ¾ cup") == "area = one half × base; three quarters cup")
        #expect(spoken("2 to 3 meters² of roof, 0.2³") == "two to three meters squared of roof, zero point two cubed")
        #expect(spoken("CO₂ and H₂O") == "CO2 and H2O")
    }

    @Test func spellsDigitRuns() {
        #expect(EnglishTextNormalizer.spokenDigits("4000") == "four thousand")
        #expect(EnglishTextNormalizer.spokenDigits("19") == "nineteen")
        #expect(EnglishTextNormalizer.spokenDigits("007") == "zero zero seven")
        #expect(EnglishTextNormalizer.spokenDigits("٣") == "three")
        #expect(EnglishTextNormalizer.spokenDigits("½") == "")
    }

    @Test func phonemizerNeverSendsDigitsToTheModel() throws {
        let lexicon = ["four": "fˈɔɹ", "thousand": "θˈWzᵊnd", "nineteen": "nˌInˈtin", "two": "tˈu", "twelve": "twˈɛlv",
                       "x": "ˈɛks", "milligrams": "mˈɪlɪɡɹˌæmz", "zero": "zˈɪɹO", "seven": "sˈɛvᵊn"]
        let phonemizer = EnglishPhonemizer(
            wordToPhonemes: lexicon,
            caseSensitiveWordToPhonemes: ["B": "bˈi"],
            allowedPunctuation: [",", "."])
        var modelWords: [String] = []
        func phonemes(_ text: String) throws -> String {
            try phonemizer.phonemize(text) { word in
                modelWords.append(word)
                return ["?"]
            }
        }
        #expect(try phonemes("4000 milligrams") == "fˈɔɹ θˈWzᵊnd mˈɪlɪɡɹˌæmz")
        #expect(try phonemes("4x4") == "fˈɔɹ ˈɛks fˈɔɹ")
        #expect(try phonemes("B12") == "bˈi twˈɛlv")
        #expect(try phonemes("007, 2½") == "zˈɪɹO zˈɪɹO sˈɛvᵊn, tˈu")
        #expect(try phonemes("COVID-19") == "? nˌInˈtin")
        #expect(modelWords == ["covid"])
        #expect(!modelWords.joined().contains { $0.isNumber })
    }

    @Test(.enabled(if: KokoroVoice.resourcesURL != nil, "Run scripts/fetch-kokoro.sh first"))
    func frontendSaysHandbookNumbersAsWords() async throws {
        let frontend = try KokoroEnglishFrontend(assetsDirectory: try #require(KokoroVoice.resourcesURL).appendingPathComponent("g2p"))
        // Text as SpokenText hands it over, against the words a person would say.
        let pairs = [
            ("Wet droppings with 1 to 10 bleach.", "Wet droppings with one to ten bleach."),
            ("Continue cycles of 30 to 2.", "Continue cycles of thirty to two."),
            ("At most 4000 milligrams, or 4,000 milligrams.", "At most four thousand milligrams, or four thousand milligrams."),
            ("Use 20 percent less, 20% less.", "Use twenty percent less, twenty percent less."),
            ("Hold grain at minus 18 degrees Celsius.", "Hold grain at minus eighteen degrees Celsius."),
            ("Repeat every 4 to 6 hours.", "Repeat every four to six hours."),
            ("Unscented 5 to 6 percent bleach.", "Unscented five to six percent bleach."),
            ("A 4x4 truck and B12.", "A four x four truck and B twelve."),
            ("Give 2½ tablets, then ½ teaspoon.", "Give two and a half tablets, then one half teaspoon."),
            ("Use 3 meters² of CO₂.", "Use three meters squared of CO two."),
        ]
        for (digits, words) in pairs {
            #expect(try await frontend.phonemes(for: digits) == frontend.phonemes(for: words), "\(digits)")
        }
    }
}
