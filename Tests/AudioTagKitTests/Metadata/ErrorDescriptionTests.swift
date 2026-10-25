import XCTest
import Foundation

/// The wording of the errors AudioTagKit reports (the CLI prints these), and
/// `TagChanges.isEmpty`.
final class ErrorDescriptionTests: XCTestCase {

    func testTagWriteErrorMessages() {
        XCTAssertEqual(
            TagWriteError.unsupportedFormat.description,
            "This file's format doesn't support writing yet."
        )
        XCTAssertEqual(TagWriteError.noChangesSpecified.description, "No tag changes were specified.")
        XCTAssertEqual(TagWriteError.underlying("disk full").description, "Write failed: disk full")
    }

    func testFLACParseErrorMessages() {
        XCTAssertEqual(
            FLACParseError.notFLAC.description,
            "Not a valid FLAC file (missing 'fLaC' marker)."
        )
        XCTAssertEqual(FLACParseError.truncated.description, "FLAC metadata appears truncated or corrupt.")
    }

    func testAIFFParseErrorMessages() {
        XCTAssertEqual(
            AIFFParseError.notAIFF.description,
            "Not a valid AIFF/AIFC file (missing 'FORM' marker)."
        )
        XCTAssertEqual(AIFFParseError.truncated.description, "AIFF chunk structure appears truncated or corrupt.")
    }

    func testBackupErrorMessages() {
        XCTAssertEqual(
            BackupError.sourceNotFound("/x/a.flac").description,
            "Cannot back up \u{2014} source file not found: /x/a.flac"
        )
        XCTAssertEqual(BackupError.copyFailed("no space").description, "Backup failed: no space")
    }

    func testMetadataErrorMessages() {
        XCTAssertEqual(
            MetadataError.invalidFile.description,
            "The file could not be parsed (invalid or corrupt)."
        )
        XCTAssertEqual(
            MetadataError.unsupportedFormat.description,
            "No reader available for this file format."
        )
        XCTAssertEqual(MetadataError.readFailed("boom").description, "Failed to read metadata: boom")
    }

    // MARK: - TagChanges.isEmpty

    func testNoChangesIsEmpty() {
        XCTAssertTrue(TagChanges().isEmpty)
    }

    func testEachSingleFieldMakesTheChangesNonEmpty() {
        let all: [TagChanges] = [
            TagChanges(title: "x"),
            TagChanges(artist: "x"),
            TagChanges(albumArtist: "x"),
            TagChanges(album: "x"),
            TagChanges(genre: "x"),
            TagChanges(track: "x"),
            TagChanges(year: "x"),
            TagChanges(comment: "x")
        ]

        for changes in all {
            XCTAssertFalse(changes.isEmpty)
        }
    }

    func testAnEmptyStringIsStillAChange() {
        XCTAssertFalse(TagChanges(title: "").isEmpty)
    }
}
