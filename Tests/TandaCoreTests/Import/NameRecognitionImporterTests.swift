import XCTest
import Foundation

/// How `TextListImporter` uses known orchestra/singer names.
///
/// NEEDS the test seam in `TracklibImportReferenceStore`
/// (`overrideEntriesForTesting`, see README_TESTS.md). All names are invented.
///
/// The rule under test: known names are taken out of a line only where they
/// stand on their own, never out of the middle of a title.
@MainActor
final class NameRecognitionImporterTests: XCTestCase {

    private func entry(_ name: String, _ aliases: [String] = []) -> TracklibImportReferenceEntry {
        TracklibImportReferenceEntry(name: name, aliases: [name] + aliases)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        TracklibImportReferenceStore.overrideEntriesForTesting = (
            orchestras: [entry("Alpha Trio", ["Carlos Alpha"]), entry("Beta Band")],
            singers: [entry("Singer X", ["Sam Singer"]), entry("Roberto Voz"), entry("Solo")]
        )
    }

    override func tearDownWithError() throws {
        TracklibImportReferenceStore.overrideEntriesForTesting = nil
        try super.tearDownWithError()
    }

    private func read(_ line: String) throws -> ImportedTrack {
        try XCTUnwrap(TextListImporter.parse(text: line, baseDirectory: nil).first, line)
    }

    // MARK: - With dashes

    func testOrchestraTitleAndSingerSeparatedByDashes() throws {
        let track = try read("Alpha Trio - Poema - Singer X")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
        XCTAssertEqual(track.singer, "Singer X")
    }

    func testAnAliasIsReplacedByTheCanonicalName() throws {
        let track = try read("Carlos Alpha - Poema")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
    }

    func testEnDashesWorkLikeHyphens() throws {
        let track = try read("Carlos Alpha \u{2013} Poema")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
    }

    func testRecognitionIgnoresCase() throws {
        let track = try read("ALPHA TRIO - Poema")

        XCTAssertEqual(track.artist, "Alpha Trio")
    }

    func testTitleFirstOrderIsRecognizedByTheNamesNotByPosition() throws {
        let track = try read("Poema - Alpha Trio")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
    }

    func testOnlyASingerRecognizedLeavesTheRestAsTheTitle() throws {
        let track = try read("Poema - Singer X")

        XCTAssertNil(track.artist)
        XCTAssertEqual(track.title, "Poema")
        XCTAssertEqual(track.singer, "Singer X")
    }

    func testSingleWordSingersAreTakenWhenTheyStandAloneBetweenDashes() throws {
        let track = try read("Alpha Trio - Poema - Solo")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
        XCTAssertEqual(track.singer, "Solo")
    }

    func testTwoOrchestrasJoinedByAConnectingWordCountAsNames() throws {
        let track = try read("Alpha Trio y Beta Band - Poema")

        XCTAssertEqual(track.artist, "Alpha Trio", "the first name wins")
        XCTAssertEqual(track.title, "Poema")
    }

    func testAPartThatMerelyContainsANameStaysTheTitle() throws {
        let track = try read("Alpha Trio - Flores de Beta Band")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Flores de Beta Band")
    }

    func testTitleThatEndsWithAKnownNameIsKeptWhole() throws {
        let track = try read("Alpha Trio - Poema Alpha Trio")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema Alpha Trio")
    }

    func testAMentionedSingerInsideATitlePartIsNotTaken() throws {
        let track = try read("Alpha Trio - Poema de Singer X")

        XCTAssertEqual(track.title, "Poema de Singer X")
        XCTAssertNil(track.singer)
    }

    func testIfNothingWouldBeLeftAsTheTitleTheDashRuleDecides() throws {
        let track = try read("Alpha Trio - Beta Band")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Beta Band")
    }

    func testBracketsAroundYearAndSingerStillWorkAlongsideNames() throws {
        let track = try read("Alpha Trio - Poema (Gesang: Singer X) (1936)")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Poema")
        XCTAssertEqual(track.singer, "Singer X")
        XCTAssertEqual(track.year, 1936)
    }

    // MARK: - Without dashes

    func testANameAtTheStartIsTaken() throws {
        let track = try read("Alpha Trio Por una cabeza")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Por una cabeza")
    }

    func testANameAtTheEndIsTaken() throws {
        let track = try read("Por una cabeza Alpha Trio")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Por una cabeza")
    }

    func testOrchestraAtTheStartAndSingerAtTheEnd() throws {
        let track = try read("Alpha Trio Por una cabeza Roberto Voz")

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.singer, "Roberto Voz")
        XCTAssertEqual(track.title, "Por una cabeza")
    }

    func testANameInTheMiddleOfATitleIsLeftAlone() throws {
        let track = try read("Poema de Alpha Trio y mas")

        XCTAssertNil(track.artist)
        XCTAssertEqual(track.title, "Poema de Alpha Trio y mas")
    }

    func testSingleWordSingerNamesAreNeverTakenWithoutDashes() throws {
        let track = try read("Por una cabeza Solo")

        XCTAssertNil(track.singer)
        XCTAssertEqual(track.title, "Por una cabeza Solo")
    }

    // MARK: - Seam hygiene

    func testWithoutInjectedNamesTheGenericRuleApplies() throws {
        TracklibImportReferenceStore.overrideEntriesForTesting = nil

        let track = try read("Carlos Alpha - Poema")

        XCTAssertEqual(track.artist, "Carlos Alpha", "no canonical name without reference data")
        XCTAssertEqual(track.title, "Poema")
    }
}
