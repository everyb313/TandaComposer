import XCTest
import Foundation

/// The list of a Tanda in "Tandas from ZIP" prints its own track number, so
/// `TandaImportLine.displayText` leaves out a number the line itself starts
/// with.
@MainActor
final class TandaImportLineDisplayTests: XCTestCase {

    private func shown(_ text: String) -> String {
        TandaImportLine(number: 1, text: text, song: nil, note: "", candidates: []).displayText
    }

    func testALeadingNumberWithAPeriodIsLeftOut() {
        XCTAssertEqual(shown("1. Alpha Trio - Poema"), "Alpha Trio - Poema")
        XCTAssertEqual(shown("12. Alpha Trio - Poema"), "Alpha Trio - Poema")
        XCTAssertEqual(shown("  4.   Poema"), "Poema")
    }

    func testOtherNumberSeparatorsAreLeftOutToo() {
        XCTAssertEqual(shown("3) Poema"), "Poema")
        XCTAssertEqual(shown("01 - Poema"), "Poema")
        XCTAssertEqual(shown("7 \u{2013} Poema"), "Poema")
        XCTAssertEqual(shown("7.Poema"), "Poema")
    }

    func testLinesWithoutALeadingNumberAreUnchanged() {
        XCTAssertEqual(shown("Alpha Trio - Song One.flac"), "Alpha Trio - Song One.flac")
        XCTAssertEqual(shown("Only Title"), "Only Title")
    }

    func testNumbersThatArePartOfTheTitleAreKept() {
        XCTAssertEqual(shown("2001 - A Space Song"), "2001 - A Space Song")
        XCTAssertEqual(shown("1999"), "1999")
        XCTAssertEqual(shown("3 Days"), "3 Days")
        XCTAssertEqual(shown("10.5 Hz Tone"), "10.5 Hz Tone")
    }

    func testALineThatIsOnlyANumberIsKept() {
        XCTAssertEqual(shown("1."), "1.")
        XCTAssertEqual(shown("5 -"), "5 -")
    }

    func testTheOriginalTextIsNotChanged() {
        let line = TandaImportLine(number: 1, text: "1. Poema", song: nil, note: "", candidates: [])

        XCTAssertEqual(line.text, "1. Poema")
        XCTAssertEqual(line.displayText, "Poema")
    }

    func testTheBestOfSeveralFilesNoteIsSharedWithTheView() {
        XCTAssertEqual(TandaImportResolver.bestOfSeveralFilesNote, "best of several files")
    }
}
