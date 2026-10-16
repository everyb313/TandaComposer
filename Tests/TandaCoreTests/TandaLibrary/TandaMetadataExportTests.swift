import XCTest
import Foundation

@MainActor
final class TandaMetadataExportTests: XCTestCase {

    private func export(
        songs: [Song],
        name: String = "Di Sarli 1",
        comment: String? = nil,
        savedAgainst: String? = "Default",
        to url: URL
    ) throws {
        try TandaMetadataExporter.export(
            songs: songs,
            tandaName: name,
            to: url,
            savedAt: wholeSecondDate,
            comment: comment,
            savedAgainstLibraryName: savedAgainst
        )
    }

    func testRoundTripKeepsEverything() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Tanda.json")
        let songs = [makeFullSong(id: 1), makeFullSong(id: 2, path: "/Music/b.flac"), makeFullSong(id: 3, path: "/Music/c.flac")]

        try export(songs: songs, comment: "Fast ones", to: file)
        let loaded = try TandaMetadataExporter.load(from: file)

        XCTAssertEqual(loaded.format, "TandaComposer Tanda")
        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.tandaName, "Di Sarli 1")
        XCTAssertEqual(loaded.savedAt, wholeSecondDate)
        XCTAssertEqual(loaded.comment, "Fast ones")
        XCTAssertEqual(loaded.savedAgainstLibraryName, "Default")
        XCTAssertEqual(loaded.songs, songs)
    }

    func testMissingCommentAndLibraryNameRoundTripAsNil() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Tanda.json")

        try export(songs: [], comment: nil, savedAgainst: nil, to: file)
        let loaded = try TandaMetadataExporter.load(from: file)

        XCTAssertNil(loaded.comment)
        XCTAssertNil(loaded.savedAgainstLibraryName)
    }

    func testTopLevelKeysAreWrittenInTheDocumentedOrder() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Tanda.json")
        try export(songs: [makeFullSong()], comment: "c", to: file)
        let text = try String(contentsOf: file, encoding: .utf8)

        let keys = ["\"format\"", "\"version\"", "\"tandaName\"", "\"savedAt\"", "\"comment\"", "\"savedAgainstLibraryName\"", "\"songs\""]
        let positions = try keys.map { key in
            try XCTUnwrap(text.range(of: key), "\(key) missing").lowerBound
        }

        XCTAssertEqual(positions, positions.sorted())
    }

    func testCommentWithSpecialCharactersSurvives() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Tanda.json")
        let comment = "Line 1\nLine \"2\"\t\\ caf\u{00E9}"

        try export(songs: [], comment: comment, to: file)

        XCTAssertEqual(try TandaMetadataExporter.load(from: file).comment, comment)
    }

    func testLoadingInvalidJSONThrows() throws {
        let dir = try makeTemporaryDirectory()
        let file = try writeText("{}", in: dir, named: "bad.json")

        XCTAssertThrowsError(try TandaMetadataExporter.load(from: file))
    }

    func testFileOfAnOlderVersionWithoutCommentStillLoads() throws {
        let dir = try makeTemporaryDirectory()
        let json = """
        {
          "format" : "TandaComposer Tanda",
          "version" : 1,
          "tandaName" : "Old Tanda",
          "savedAt" : "2023-11-14T22:13:20Z",
          "songs" : []
        }
        """
        let file = try writeText(json, in: dir, named: "old.json")

        let loaded = try TandaMetadataExporter.load(from: file)

        XCTAssertEqual(loaded.tandaName, "Old Tanda")
        XCTAssertNil(loaded.comment)
        XCTAssertNil(loaded.savedAgainstLibraryName)
    }
}
