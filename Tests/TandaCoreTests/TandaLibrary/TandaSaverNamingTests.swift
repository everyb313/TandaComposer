import XCTest
import Foundation

@MainActor
final class TandaSaverNamingTests: XCTestCase {

    private func fields(
        artist: String,
        genre: String,
        albumArtist: String
    ) -> TandaSaver.ResolvedFields {
        TandaSaver.ResolvedFields(artist: artist, genre: genre, albumArtist: albumArtist)
    }

    private func touch(_ name: String, in folder: URL) {
        FileManager.default.createFile(
            atPath: folder.appendingPathComponent(name).path,
            contents: Data()
        )
    }

    // MARK: - normalizedFileNameComponent

    func testDiacriticsAreRemoved() {
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("Rodr\u{00ED}guez"), "Rodriguez")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("Carlos D\u{00ED} Sarli"), "Carlos Di Sarli")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("T\u{00E1}ngo"), "Tango")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("\u{00C1}ngel"), "Angel")
    }

    func testDecomposedAccentsAreRemovedToo() {
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("Cafe\u{0301}"), "Cafe")
    }

    func testCapitalizationIsPreserved() {
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("TANGO"), "TANGO")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("tango"), "tango")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("Tango"), "Tango")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("  Tango \n"), "Tango")
    }

    func testSlashAndColonBecomeDashes() {
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("AC/DC"), "AC-DC")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("Vol: 1"), "Vol- 1")
    }

    func testEmptyValueBecomesUntitled() {
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent(""), "Untitled Tanda")
        XCTAssertEqual(TandaSaver.normalizedFileNameComponent("   \n"), "Untitled Tanda")
    }

    // MARK: - commaTruncated

    func testCommaTruncationKeepsTheTextBeforeTheFirstComma() {
        XCTAssertEqual(TandaSaver.commaTruncated("Di Sarli, Carlos"), "Di Sarli")
        XCTAssertEqual(TandaSaver.commaTruncated("Alpha, Beta, Gamma"), "Alpha")
        XCTAssertEqual(TandaSaver.commaTruncated("Alpha ,Beta"), "Alpha")
    }

    func testTextWithoutCommaIsUnchanged() {
        XCTAssertEqual(TandaSaver.commaTruncated("Alpha Trio"), "Alpha Trio")
    }

    func testLeadingCommaGivesAnEmptyString() {
        XCTAssertEqual(TandaSaver.commaTruncated(", Beta"), "")
    }

    // MARK: - suggestedName

    func testSuggestedNameJoinsArtistGenreAndAlbumArtist() throws {
        let folder = try makeTemporaryDirectory()
        let name = TandaSaver.suggestedName(
            fields: fields(artist: "Carlos D\u{00ED} Sarli", genre: "T\u{00E1}ngo", albumArtist: "Carlos Di Sarli"),
            availableIn: folder
        )

        XCTAssertEqual(name, "Carlos Di Sarli_Tango_Carlos Di Sarli")
    }

    func testSuggestedNameUsesOnlyTheFirstArtistBeforeAComma() throws {
        let folder = try makeTemporaryDirectory()
        let name = TandaSaver.suggestedName(
            fields: fields(artist: "Di Sarli, Carlos", genre: "Tango", albumArtist: "Dur\u{00E1}n, Roberto"),
            availableIn: folder
        )

        XCTAssertEqual(name, "Di Sarli_Tango_Duran")
    }

    func testGenreIsNotTruncatedAtAComma() throws {
        let folder = try makeTemporaryDirectory()
        let name = TandaSaver.suggestedName(
            fields: fields(artist: "Alpha Trio", genre: "Tango, Vals", albumArtist: "Beta"),
            availableIn: folder
        )

        XCTAssertEqual(name, "Alpha Trio_Tango, Vals_Beta")
    }

    func testPathSeparatorsInNamesAreReplaced() throws {
        let folder = try makeTemporaryDirectory()
        let name = TandaSaver.suggestedName(
            fields: fields(artist: "AC/DC", genre: "Rock", albumArtist: "AC/DC"),
            availableIn: folder
        )

        XCTAssertEqual(name, "AC-DC_Rock_AC-DC")
    }

    // MARK: - Collisions

    private var sample: TandaSaver.ResolvedFields {
        fields(artist: "Alpha Trio", genre: "Tango", albumArtist: "Beta")
    }

    private let base = "Alpha Trio_Tango_Beta"

    func testFreeNameIsUsedAsIs() throws {
        let folder = try makeTemporaryDirectory()

        XCTAssertEqual(TandaSaver.suggestedName(fields: sample, availableIn: folder), base)
    }

    func testExistingFileGetsOrdinalTwo() throws {
        let folder = try makeTemporaryDirectory()
        touch("\(base).json", in: folder)

        XCTAssertEqual(TandaSaver.suggestedName(fields: sample, availableIn: folder), "\(base)_2")
    }

    func testOrdinalsCountUpUntilFree() throws {
        let folder = try makeTemporaryDirectory()
        touch("\(base).json", in: folder)
        touch("\(base)_2.json", in: folder)

        XCTAssertEqual(TandaSaver.suggestedName(fields: sample, availableIn: folder), "\(base)_3")
    }

    func testFirstFreeOrdinalIsUsedEvenIfALaterOneExists() throws {
        let folder = try makeTemporaryDirectory()
        touch("\(base).json", in: folder)
        touch("\(base)_3.json", in: folder)

        XCTAssertEqual(TandaSaver.suggestedName(fields: sample, availableIn: folder), "\(base)_2")
    }

    func testOnlyJSONFilesCauseCollisions() throws {
        let folder = try makeTemporaryDirectory()
        touch("\(base).txt", in: folder)

        XCTAssertEqual(TandaSaver.suggestedName(fields: sample, availableIn: folder), base)
    }

    func testExcludedFileDoesNotCollideWithItself() throws {
        let folder = try makeTemporaryDirectory()
        touch("\(base).json", in: folder)
        let own = folder.appendingPathComponent("\(base).json")

        XCTAssertEqual(
            TandaSaver.suggestedName(fields: sample, availableIn: folder, excluding: own),
            base
        )
    }

    func testExcludingADifferentFileStillCollides() throws {
        let folder = try makeTemporaryDirectory()
        touch("\(base).json", in: folder)
        let other = folder.appendingPathComponent("Something Else.json")

        XCTAssertEqual(
            TandaSaver.suggestedName(fields: sample, availableIn: folder, excluding: other),
            "\(base)_2"
        )
    }
}
