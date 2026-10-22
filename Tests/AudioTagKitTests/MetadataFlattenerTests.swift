import XCTest
import Foundation

final class MetadataFlattenerP2Tests: XCTestCase {
    func testMapsKnownTopLevelGroups() {
        let rows = MetadataFlattener.flatten([
            "vorbisComments": ["TITLE": "Song"],
            "streamInfo": ["sampleRate": 44100],
            "common": ["artist": "Artist"],
            "format": "FLAC",
            "durationSeconds": 12.5,
            "hasArtwork": true
        ])
        XCTAssertTrue(rows.contains { $0.group == "VorbisComment" && $0.key == "TITLE" && $0.value == "Song" })
        XCTAssertTrue(rows.contains { $0.group == "StreamInfo" && $0.key == "sampleRate" })
        XCTAssertTrue(rows.contains { $0.group == "Common" && $0.key == "artist" })
        XCTAssertTrue(rows.contains { $0.group == "File" && $0.key == "format" && $0.value == "FLAC" })
        XCTAssertTrue(rows.contains { $0.group == "File" && $0.key == "durationSeconds" })
        XCTAssertTrue(rows.contains { $0.group == "Artwork" && $0.key == "hasArtwork" })
    }

    func testFormatSpecificFieldsUseFormatNameAsGroup() {
        let rows = MetadataFlattener.flatten([
            "formatSpecific": ["id3 ": ["TIT2": "Song", "TPE1": "Artist"]]
        ])
        XCTAssertTrue(rows.contains { $0.group == "id3 " && $0.key == "TIT2" && $0.value == "Song" })
        XCTAssertTrue(rows.contains { $0.group == "id3 " && $0.key == "TPE1" && $0.value == "Artist" })
    }

    func testRowsAreSortedByGroupThenKey() {
        let rows = MetadataFlattener.flatten([
            "common": ["z": "last", "a": "first"],
            "vorbisComments": ["B": "b", "A": "a"]
        ])
        XCTAssertEqual(rows.map { "\($0.group)|\($0.key)" }, rows.map { "\($0.group)|\($0.key)" }.sorted())
    }

    func testScalarTopLevelValuesBecomeRows() {
        let rows = MetadataFlattener.flatten(["customField": 42])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].group, "Other")
        XCTAssertEqual(rows[0].key, "customField")
        XCTAssertEqual(rows[0].value, "42")
    }
}
