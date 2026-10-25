import XCTest
import Foundation

/// "Instrumental" in a text list is an explicit singer value, not a missing
/// singer: the bare words (and "instr.") in brackets, with or without a
/// "Gesang:"-style label, become the singer "Instrumental".
@MainActor
final class TextListImporterInstrumentalTests: XCTestCase {

    private func read(_ line: String) throws -> ImportedTrack {
        try XCTUnwrap(TextListImporter.parse(text: line, baseDirectory: nil).first, line)
    }

    func testBareInstrumentalInBracketsBecomesTheSinger() throws {
        let track = try read("Alpha Trio - Poema (Instrumental)")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
        XCTAssertEqual(track.singer, "Instrumental")
    }

    func testAbbreviationsAndCaseAreCanonicalized() throws {
        for spelling in ["instr.", "INSTR", "Instr.", "instrumental", "INSTRUMENTAL"] {
            let track = try read("Alpha Trio - Poema (\(spelling))")

            XCTAssertEqual(track.singer, "Instrumental", spelling)
            XCTAssertEqual(track.title, "Poema", spelling)
        }
    }

    func testLabelledInstrumentalBecomesTheSingerToo() throws {
        for line in [
            "Alpha Trio - Poema (Gesang: Instrumental)",
            "Alpha Trio - Poema (Singer: instr.)",
            "Alpha Trio - Poema (Vocals - Instrumental)"
        ] {
            let track = try read(line)

            XCTAssertEqual(track.singer, "Instrumental", line)
            XCTAssertEqual(track.title, "Poema", line)
        }
    }

    func testYearAndInstrumentalCanBothBeGiven() throws {
        let track = try read("Alpha Trio - Poema (Instrumental) (1936)")

        XCTAssertEqual(track.singer, "Instrumental")
        XCTAssertEqual(track.year, 1936)
        XCTAssertEqual(track.title, "Poema")
    }

    func testANamedSingerIsUnchanged() throws {
        let track = try read("Alpha Trio - Poema (Gesang: Singer X)")

        XCTAssertEqual(track.singer, "Singer X")
    }

    func testOtherBracketTextIsNotTakenAsASinger() throws {
        let track = try read("Alpha Trio - Poema (remastered)")

        XCTAssertNil(track.singer)
    }

    func testAMerelySimilarWordIsNotTheInstrumentalMarker() throws {
        let track = try read("Alpha Trio - Poema (Instrumentale)")

        XCTAssertNil(track.singer)
    }
}
