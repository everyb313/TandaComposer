import XCTest
import Foundation

/// The Setlist file format is shared with older app versions and with
/// backups, so keys and values are pinned here.
@MainActor
final class SetlistMetadataExportTests: XCTestCase {

    private func export(
        songs: [Song],
        name: String = "Friday",
        savedAgainst: String? = "Default",
        to url: URL
    ) throws {
        try SetlistMetadataExporter.export(
            songs: songs,
            setlistName: name,
            to: url,
            savedAt: wholeSecondDate,
            savedAgainstLibraryName: savedAgainst
        )
    }

    func testRoundTripKeepsEverythingIncludingAllSongFields() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Friday.json")
        let songs = [makeFullSong(id: 7), makeFullSong(id: nil, path: "/Music/second.flac")]

        try export(songs: songs, to: file)
        let loaded = try SetlistMetadataExporter.load(from: file)

        XCTAssertEqual(loaded.format, "TandaComposer Setlist")
        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.setlistName, "Friday")
        XCTAssertEqual(loaded.savedAt, wholeSecondDate)
        XCTAssertEqual(loaded.savedAgainstLibraryName, "Default")
        XCTAssertEqual(loaded.songs, songs)
    }

    func testEmptySetlistRoundTrips() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Empty.json")

        try export(songs: [], name: "Empty", to: file)
        let loaded = try SetlistMetadataExporter.load(from: file)

        XCTAssertEqual(loaded.setlistName, "Empty")
        XCTAssertTrue(loaded.songs.isEmpty)
    }

    func testNilLibraryNameRoundTripsAsNil() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("a.json")

        try export(songs: [], savedAgainst: nil, to: file)

        XCTAssertNil(try SetlistMetadataExporter.load(from: file).savedAgainstLibraryName)
    }

    func testNameKeyOnDiskIsStillCalledPlaylistName() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Friday.json")
        try export(songs: [], to: file)

        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("\"playlistName\" : \"Friday\""))
        XCTAssertFalse(text.contains("setlistName"))
    }

    func testTopLevelKeysAreWrittenInTheDocumentedOrder() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Friday.json")
        try export(songs: [makeFullSong()], to: file)
        let text = try String(contentsOf: file, encoding: .utf8)

        let keys = ["\"format\"", "\"version\"", "\"playlistName\"", "\"savedAt\"", "\"savedAgainstLibraryName\"", "\"songs\""]
        let positions = try keys.map { key in
            try XCTUnwrap(text.range(of: key), "\(key) missing").lowerBound
        }

        XCTAssertEqual(positions, positions.sorted())
    }

    func testDatesAreWrittenAsISO8601Strings() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Friday.json")
        try export(songs: [makeFullSong()], to: file)
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertTrue(text.contains("\"savedAt\" : \"2023-11-14T22:13:20Z\""))
        XCTAssertTrue(text.contains("\"addedToLibrary\" : \"2023-11-14T22:13:20Z\""))
    }

    func testFileIsValidJSON() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Friday.json")
        try export(songs: [makeFullSong(id: 1), makeFullSong(id: 2, path: "/Music/b.flac")], to: file)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]

        XCTAssertEqual((object?["songs"] as? [Any])?.count, 2)
    }

    func testFileWrittenByAnOlderVersionStillLoads() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("old.json")
        let json = """
        {
          "format" : "TandaComposer Setlist",
          "version" : 1,
          "playlistName" : "Old Set",
          "savedAt" : "2023-11-14T22:13:20Z",
          "songs" : [
            {
              "id" : 5,
              "filename" : "a.flac",
              "path" : "/Music/a.flac",
              "normalizedPath" : "/Music/a.flac",
              "title" : "A",
              "addedToLibrary" : "2023-11-14T22:13:20Z",
              "lastLibraryScan" : "2023-11-14T22:13:20Z",
              "fileModificationDateAtScan" : "2023-11-14T22:13:20Z",
              "fileSizeAtScan" : 10
            }
          ]
        }
        """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let loaded = try SetlistMetadataExporter.load(from: file)

        XCTAssertEqual(loaded.setlistName, "Old Set")
        XCTAssertNil(loaded.savedAgainstLibraryName, "files from before this key existed have none")
        XCTAssertEqual(loaded.songs.first?.title, "A")
        XCTAssertEqual(loaded.songs.first?.id, 5)
    }

    func testLoadingInvalidJSONThrows() throws {
        let dir = try makeTemporaryDirectory()
        let file = try writeText("not json", in: dir, named: "bad.json")

        XCTAssertThrowsError(try SetlistMetadataExporter.load(from: file))
    }

    func testLoadingAMissingFileThrows() throws {
        let dir = try makeTemporaryDirectory()

        XCTAssertThrowsError(try SetlistMetadataExporter.load(from: dir.appendingPathComponent("nope.json")))
    }

    func testExportingIntoAMissingFolderThrows() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("missing/folder/a.json")

        XCTAssertThrowsError(try export(songs: [], to: file))
    }

    func testExportReplacesAnExistingFile() throws {
        let dir = try makeTemporaryDirectory()
        let file = dir.appendingPathComponent("Friday.json")
        try export(songs: [makeFullSong(path: "/Music/one.flac")], to: file)

        try export(songs: [makeFullSong(path: "/Music/two.flac"), makeFullSong(path: "/Music/three.flac")], to: file)

        XCTAssertEqual(try SetlistMetadataExporter.load(from: file).songs.count, 2)
    }
}
