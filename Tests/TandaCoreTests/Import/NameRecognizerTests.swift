import XCTest
import Foundation

/// Rules of the name recognizer behind `TracklibImportReferenceStore`:
/// whole words only, case/accent/apostrophe/whitespace tolerant, longest
/// spelling wins, left to right without overlap, shared spellings resolved
/// by the entry whose own name they contain, and fast on long lists.
///
/// NEEDS 3 ACCESS-LEVEL EDITS in TandaCore/Import/TracklibImportReference.swift
/// (remove the word `private`), see README_TESTS.md:
///   `nonisolated private struct NameRecognizer`          -> `nonisolated struct NameRecognizer`
///   `nonisolated private static func patternFragment`    -> `nonisolated static func patternFragment`
///   `nonisolated private func foldReferenceName`         -> `nonisolated func foldReferenceName`
@MainActor
final class NameRecognizerTests: XCTestCase {

    // MARK: - Helpers

    private func entry(_ name: String, _ aliases: [String]) -> TracklibImportReferenceEntry {
        TracklibImportReferenceEntry(name: name, aliases: aliases)
    }

    private lazy var recognizer = NameRecognizer(entries: [
        entry("Biagi", ["Biagi", "Rodolfo Biagi"]),
        entry("Calo", ["Calo", "Cal\u{00F3}", "Miguel Cal\u{00F3}", "Miguel Calo"]),
        entry("D'Arienzo", ["D'Arienzo", "Juan D'Arienzo"]),
        entry("Di Sarli", ["Di Sarli", "Carlos Di Sarli"])
    ])

    private func names(_ text: String, using custom: NameRecognizer? = nil) -> [String] {
        (custom ?? recognizer).matches(in: text).map { $0.entry.name }
    }

    private func matchedTexts(_ text: String) -> [String] {
        recognizer.matches(in: text).map { String(text[$0.range]) }
    }

    // MARK: - Finding names

    func testFindsAKnownName() {
        XCTAssertEqual(names("Biagi - Poema"), ["Biagi"])
        XCTAssertEqual(matchedTexts("Biagi - Poema"), ["Biagi"])
    }

    func testReturnsTheCanonicalNameForAnAlias() {
        XCTAssertEqual(names("Rodolfo Biagi - Poema"), ["Biagi"])
    }

    func testTheLongestSpellingWinsAtOnePosition() {
        XCTAssertEqual(matchedTexts("Rodolfo Biagi - Poema"), ["Rodolfo Biagi"])
        XCTAssertEqual(matchedTexts("Carlos Di Sarli - Bahia Blanca"), ["Carlos Di Sarli"])
    }

    func testIgnoresCase() {
        XCTAssertEqual(names("BIAGI"), ["Biagi"])
        XCTAssertEqual(names("biagi"), ["Biagi"])
        XCTAssertEqual(names("rodolfo BIAGI"), ["Biagi"])
    }

    func testFindsTheNameWithAndWithoutAccents() {
        XCTAssertEqual(names("Cal\u{00F3} - Poema"), ["Calo"])
        XCTAssertEqual(names("Calo - Poema"), ["Calo"])
        XCTAssertEqual(matchedTexts("Miguel Cal\u{00F3}"), ["Miguel Cal\u{00F3}"])
        XCTAssertEqual(matchedTexts("Miguel Calo"), ["Miguel Calo"])
    }

    func testAllApostropheVariantsAreTheSameName() {
        for apostrophe in ["'", "\u{2019}", "\u{2018}", "\u{00B4}", "`"] {
            XCTAssertEqual(names("D\(apostrophe)Arienzo - Poema"), ["D'Arienzo"], apostrophe)
        }
    }

    func testRunsOfWhiteSpaceInTheTextAreTolerated() {
        XCTAssertEqual(names("Rodolfo   Biagi"), ["Biagi"])
        XCTAssertEqual(names("Rodolfo\tBiagi"), ["Biagi"])
        XCTAssertEqual(names("Di  Sarli"), ["Di Sarli"])
    }

    // MARK: - Boundaries

    func testDoesNotMatchInsideALongerWord() {
        XCTAssertTrue(names("Biagini").isEmpty)
        XCTAssertTrue(names("xBiagi").isEmpty)
        XCTAssertTrue(names("Biagi2").isEmpty)
        XCTAssertTrue(names("Caloric").isEmpty)
    }

    func testPunctuationAroundANameIsFine() {
        XCTAssertEqual(names("(Biagi)"), ["Biagi"])
        XCTAssertEqual(names("Poema, Biagi."), ["Biagi"])
        XCTAssertEqual(names("Biagi/Calo"), ["Biagi", "Calo"])
    }

    func testSeveralNamesAreReturnedLeftToRightWithoutOverlap() {
        XCTAssertEqual(names("Biagi - Calo - Di Sarli"), ["Biagi", "Calo", "Di Sarli"])
        XCTAssertEqual(names("Rodolfo Biagi y Miguel Cal\u{00F3}"), ["Biagi", "Calo"])
    }

    func testTheSameNameTwiceIsFoundTwice() {
        XCTAssertEqual(names("Biagi, Biagi"), ["Biagi", "Biagi"])
    }

    func testRangesPointIntoTheGivenText() {
        let text = "Poema - Biagi (1936)"

        let range = recognizer.matches(in: text).first?.range

        XCTAssertEqual(range.map { String(text[$0]) }, "Biagi")
    }

    // MARK: - Degenerate input

    func testEmptyTextHasNoMatches() {
        XCTAssertTrue(names("").isEmpty)
    }

    func testTextWithoutKnownNamesHasNoMatches() {
        XCTAssertTrue(names("Alpha Trio - Song One").isEmpty)
    }

    func testRecognizerWithoutEntriesMatchesNothing() {
        let empty = NameRecognizer(entries: [])

        XCTAssertTrue(names("Biagi", using: empty).isEmpty)
    }

    func testEntriesWithOnlyBlankSpellingsMatchNothingAndDoNotCrash() {
        let blank = NameRecognizer(entries: [entry("", [""]), entry("  ", ["   "])])

        XCTAssertTrue(names("Biagi", using: blank).isEmpty)
    }

    func testRegexMetacharactersInNamesAreTakenLiterally() {
        let custom = NameRecognizer(entries: [entry("Mr. X+Y", ["Mr. X+Y"])])

        XCTAssertEqual(names("with Mr. X+Y live", using: custom), ["Mr. X+Y"])
        XCTAssertTrue(names("Mr, X+Y", using: custom).isEmpty, "the dot is not a wildcard")
        XCTAssertTrue(names("Mr. XXY", using: custom).isEmpty, "the plus is not a quantifier")
    }

    // MARK: - Shared spellings

    func testASpellingListedUnderTwoEntriesGoesToTheOneWhoseNameItContains() {
        let solo = entry("Solo", ["Solo", "Pepe Gomez"])
        let gomez = entry("Gomez", ["Gomez", "Pepe Gomez"])

        for order in [[solo, gomez], [gomez, solo]] {
            let custom = NameRecognizer(entries: order)

            XCTAssertEqual(names("Pepe Gomez", using: custom), ["Gomez"])
            XCTAssertEqual(names("Solo", using: custom), ["Solo"])
            XCTAssertEqual(names("Gomez", using: custom), ["Gomez"])
        }
    }

    // MARK: - Helpers of the recognizer

    func testFoldReferenceNameIgnoresCaseAccentsApostrophesDashesAndSpacing() {
        XCTAssertEqual(foldReferenceName("Cal\u{00F3}"), "calo")
        XCTAssertEqual(foldReferenceName("\u{00D1}and\u{00FA}"), "nandu")
        XCTAssertEqual(foldReferenceName("D\u{2019}Arienzo"), "d'arienzo")
        XCTAssertEqual(foldReferenceName("D`Arienzo"), "d'arienzo")
        XCTAssertEqual(foldReferenceName("A \u{2013} B"), "a - b")
        XCTAssertEqual(foldReferenceName("A \u{2014} B"), "a - b")
        XCTAssertEqual(foldReferenceName("  A   B  "), "a b")
    }

    func testPatternFragmentEscapesMetacharactersAndLoosensSpacesAndApostrophes() {
        XCTAssertEqual(NameRecognizer.patternFragment("A  B"), "A\\s+B")
        XCTAssertEqual(NameRecognizer.patternFragment("a.b"), "a\\.b")
        XCTAssertEqual(NameRecognizer.patternFragment("x+y"), "x\\+y")
        XCTAssertEqual(
            NameRecognizer.patternFragment("D'x"),
            "D['\u{2019}\u{2018}\u{00B4}`]x"
        )
    }

    // MARK: - Speed

    /// Guards against compiling one regular expression per alias and per
    /// call, which made long import lists take minutes. The limit is
    /// generous; the compiled recognizer needs a fraction of it.
    func testLongListsAreRecognizedQuickly() {
        func letters(_ number: Int) -> String {
            var value = number
            var result = ""

            repeat {
                result.append(Character(UnicodeScalar(UInt8(97 + value % 26))))
                value /= 26
            } while value > 0

            return result
        }

        let entries = (0..<150).map { index -> TracklibImportReferenceEntry in
            let name = "Orq" + letters(index)

            return entry(name, [name, "Maestro " + name, name + " y su Orquesta"])
        }

        let custom = NameRecognizer(entries: entries)
        let started = Date()
        var found = 0

        for index in 0..<1_000 {
            let name = "Orq" + letters(index % 150)

            if !custom.matches(in: "\(index + 1). \(name) - Song \(index)").isEmpty {
                found += 1
            }
        }

        XCTAssertEqual(found, 1_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
