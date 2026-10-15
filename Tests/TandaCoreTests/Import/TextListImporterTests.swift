import XCTest
import Foundation

/// The fixtures use invented orchestra names ("Alpha Trio", "Beta Band") on
/// purpose. In the test bundle `Bundle.main` is the test runner, which does
/// not contain `tracklib_import_reference.json`, so name recognition has no
/// reference data here. These tests therefore cover the generic
/// line-reading rules only, independent of the bundled name list.
@MainActor
final class TextListImporterTests: XCTestCase {

    private func parse(_ lines: String..., baseDirectory: URL? = nil) -> [ImportedTrack] {
        TextListImporter.parse(text: lines.joined(separator: "\n"), baseDirectory: baseDirectory)
    }

    // MARK: - Single line shapes

    func testArtistDashTitleWithoutSuffix() throws {
        let tracks = parse("Alpha Trio - Song One")

        XCTAssertEqual(tracks.count, 1)
        let track = try XCTUnwrap(tracks.first)
        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song One")
        XCTAssertNil(track.path)
        XCTAssertNil(track.filename, "a name without audio suffix is no file name")
        XCTAssertEqual(track.sourceDisplayName, "Alpha Trio - Song One")
        XCTAssertNil(track.year)
        XCTAssertNil(track.singer)
    }

    func testFileNameWithSuffixKeepsFilename() throws {
        let track = try XCTUnwrap(parse("Alpha Trio - Song One.flac").first)

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song One")
        XCTAssertEqual(track.filename, "Alpha Trio - Song One.flac")
        XCTAssertNil(track.path)
    }

    func testAbsolutePathIsKept() throws {
        let track = try XCTUnwrap(parse("/Music/Tango/Alpha Trio - Song One.flac").first)

        XCTAssertEqual(track.path, "/Music/Tango/Alpha Trio - Song One.flac")
        XCTAssertEqual(track.filename, "Alpha Trio - Song One.flac")
        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song One")
    }

    func testFileURLIsDecoded() throws {
        let encoded = try XCTUnwrap(parse("file:///Music/Alpha%20Trio%20-%20Song%20One.flac").first)
        XCTAssertEqual(encoded.path, "/Music/Alpha Trio - Song One.flac")
        XCTAssertEqual(encoded.title, "Song One")

        let withSpaces = try XCTUnwrap(parse("file:///Music/Alpha Trio - Song One.flac").first)
        XCTAssertEqual(withSpaces.path, "/Music/Alpha Trio - Song One.flac")
    }

    func testWindowsPathKeepsOnlyTheFileName() throws {
        let track = try XCTUnwrap(parse("C:\\Music\\Tango\\Alpha Trio - Song One.flac").first)

        XCTAssertNil(track.path, "a Windows path cannot be used on this Mac")
        XCTAssertEqual(track.filename, "Alpha Trio - Song One.flac")
        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song One")
    }

    func testRelativePathWithAudioSuffixIsResolvedAgainstBaseDirectory() throws {
        let base = URL(fileURLWithPath: "/Music/Lists", isDirectory: true)
        let track = try XCTUnwrap(
            parse("Tango/Alpha Trio - Song One.flac", baseDirectory: base).first
        )

        XCTAssertEqual(track.path, "/Music/Lists/Tango/Alpha Trio - Song One.flac")
        XCTAssertEqual(track.filename, "Alpha Trio - Song One.flac")
    }

    func testSlashInsideATitleIsNotAPath() throws {
        let track = try XCTUnwrap(parse("AC/DC - Thunderstruck").first)

        XCTAssertNil(track.path)
        XCTAssertEqual(track.artist, "AC/DC")
        XCTAssertEqual(track.title, "Thunderstruck")
    }

    func testQuotedLinesAreUnquoted() throws {
        let double = try XCTUnwrap(parse("\"Alpha Trio - Song One.flac\"").first)
        XCTAssertEqual(double.filename, "Alpha Trio - Song One.flac")

        let single = try XCTUnwrap(parse("'Alpha Trio - Song One'").first)
        XCTAssertEqual(single.artist, "Alpha Trio")
        XCTAssertEqual(single.title, "Song One")
    }

    func testSingleWordIsATitleWithoutArtist() throws {
        let track = try XCTUnwrap(parse("Poema").first)

        XCTAssertNil(track.artist)
        XCTAssertEqual(track.title, "Poema")
    }

    func testEnDashSeparatesArtistAndTitle() throws {
        let track = try XCTUnwrap(parse("Alpha Trio \u{2013} Song One").first)

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song One")
    }

    // MARK: - Year, singer, brackets

    func testYearAndSingerBracketsAreTakenOutOfTheTitle() throws {
        let track = try XCTUnwrap(parse("Alpha Trio - Song Two (Gesang: Singer X) (1938)").first)

        XCTAssertEqual(track.artist, "Alpha Trio")
        XCTAssertEqual(track.title, "Song Two")
        XCTAssertEqual(track.singer, "Singer X")
        XCTAssertEqual(track.year, 1938)
    }

    func testUnknownBracketStaysInTheTitle() throws {
        let track = try XCTUnwrap(parse("Alpha Trio - Song One (Remastered)").first)

        XCTAssertEqual(track.title, "Song One (Remastered)")
        XCTAssertNil(track.year)
        XCTAssertNil(track.singer)
    }

    func testYearOnlyLine() throws {
        let track = try XCTUnwrap(parse("Alpha Trio - Song One (1937)").first)

        XCTAssertEqual(track.title, "Song One")
        XCTAssertEqual(track.year, 1937)
    }

    // MARK: - List numbers

    func testLeadingListNumbersAreRemoved() throws {
        for line in ["1. Alpha Trio - Song One", "12) Alpha Trio - Song One", "01 - Alpha Trio - Song One"] {
            let track = try XCTUnwrap(parse(line).first, line)

            XCTAssertEqual(track.artist, "Alpha Trio", line)
            XCTAssertEqual(track.title, "Song One", line)
        }
    }

    func testNumberedListIgnoresHeadingsRemarksAndCortinas() {
        let tracks = parse(
            "Format: Artist - Song",
            "TANDA 1: Alpha Trio",
            "1. Alpha Trio - Song One (1937)",
            "2. Alpha Trio - Song Two (Gesang: Singer X) (1938)",
            "3. Alpha Trio - Song Three",
            "4. Alpha Trio - Song Four",
            "--- Cortina ---",
            "Cortina 1 (Some Jingle)",
            "Viel Spass beim Tanzen"
        )

        XCTAssertEqual(tracks.map(\.title), ["Song One", "Song Two", "Song Three", "Song Four"])
        XCTAssertEqual(tracks.map(\.sourceIndex), [0, 1, 2, 3])
        XCTAssertEqual(tracks[0].year, 1937)
        XCTAssertEqual(tracks[1].singer, "Singer X")
    }

    func testNumberedListStillAcceptsUnnumberedFileNames() {
        let tracks = parse(
            "1. Alpha Trio - Song One",
            "2. Alpha Trio - Song Two",
            "3. Alpha Trio - Song Three",
            "Beta Band - Song Four.flac",
            "A remark that is no track"
        )

        XCTAssertEqual(tracks.count, 4)
        XCTAssertEqual(tracks.last?.filename, "Beta Band - Song Four.flac")
    }

    // MARK: - Structure, comments, empty input

    func testStructureLinesAreIgnoredInAPlainList() {
        let tracks = parse(
            "[Tanda 1]",
            "Alpha Trio - Song One",
            "--- Cortina ---",
            "Beta Band - Song Two",
            "Orchester: Gamma Sextet",
            "==========",
            "--> remark"
        )

        XCTAssertEqual(tracks.map(\.title), ["Song One", "Song Two"])
        XCTAssertEqual(tracks.map(\.sourceIndex), [0, 1])
    }

    func testCommentsAndBlankLinesAreIgnored() {
        let tracks = parse(
            "# my set",
            "",
            "Alpha Trio - Song One",
            "   ",
            "# another comment",
            "Beta Band - Song Two"
        )

        XCTAssertEqual(tracks.count, 2)
    }

    func testEmptyAndCommentOnlyInputYieldNoTracks() {
        XCTAssertTrue(TextListImporter.parse(text: "", baseDirectory: nil).isEmpty)
        XCTAssertTrue(TextListImporter.parse(text: "\n\n  \n", baseDirectory: nil).isEmpty)
        XCTAssertTrue(TextListImporter.parse(text: "# nothing here", baseDirectory: nil).isEmpty)
    }

    // MARK: - Declared order

    func testTitleFirstOrderDeclaration() {
        let tracks = parse(
            "Format: Song - Artist",
            "Song One - Alpha Trio",
            "Song Two - Beta Band"
        )

        XCTAssertEqual(tracks.map(\.artist), ["Alpha Trio", "Beta Band"])
        XCTAssertEqual(tracks.map(\.title), ["Song One", "Song Two"])
    }

    func testArtistFirstOrderDeclaration() {
        let tracks = parse(
            "Format: Interpret - Titel",
            "Alpha Trio - Song One"
        )

        XCTAssertEqual(tracks.first?.artist, "Alpha Trio")
        XCTAssertEqual(tracks.first?.title, "Song One")
    }

    // MARK: - Reading from files (encodings)

    func testUTF8FileIsRead() throws {
        let dir = try makeTemporaryDirectory()
        let file = try writeText("Alpha Trio - Song One\nBeta Band - Song Two\n", in: dir, named: "list.txt")

        let tracks = try TextListImporter.importTracks(from: file)

        XCTAssertEqual(tracks.map(\.title), ["Song One", "Song Two"])
    }

    func testUTF16FileWithBOMIsRead() throws {
        let dir = try makeTemporaryDirectory()
        let data = try XCTUnwrap("Alpha Trio - Song One\nBeta Band - Song Two".data(using: .utf16))
        let file = try writeData(data, in: dir, named: "list.txt")

        let tracks = try TextListImporter.importTracks(from: file)

        XCTAssertEqual(tracks.map(\.title), ["Song One", "Song Two"])
    }

    func testLatin1FileIsReadAsFallback() throws {
        let dir = try makeTemporaryDirectory()
        let data = try XCTUnwrap("Alpha Trio - Caf\u{00E9}".data(using: .isoLatin1))
        let file = try writeData(data, in: dir, named: "list.txt")

        let tracks = try TextListImporter.importTracks(from: file)

        XCTAssertEqual(tracks.first?.title, "Caf\u{00E9}")
    }

    func testRelativePathsInAFileUseTheFilesFolderAsBase() throws {
        let dir = try makeTemporaryDirectory()
        let file = try writeText("Tango/Alpha Trio - Song One.flac\n", in: dir, named: "list.txt")

        let tracks = try TextListImporter.importTracks(from: file)

        XCTAssertEqual(
            tracks.first?.path,
            dir.appendingPathComponent("Tango/Alpha Trio - Song One.flac").standardizedFileURL.path
        )
    }

    func testMissingFileThrows() throws {
        let dir = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try TextListImporter.importTracks(from: dir.appendingPathComponent("nope.txt"))
        )
    }
}
