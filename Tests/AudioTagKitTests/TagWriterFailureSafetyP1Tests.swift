/*
import XCTest
import Foundation

/// P1 safety tests for the public write/strip orchestration.
/// These deliberately use malformed files with recognizable container signatures:
/// dispatch should select the correct writer, the operation should fail, and
/// the original backup and source bytes should remain exact.
final class TagWriterFailureSafetyP1Tests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TagWriterFailureSafetyP1-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testMalformedFLACWriteKeepsSourceAndFirstBackupByteForByte() async throws {
        let source = temporaryDirectory.appendingPathComponent("broken.flac")
        // Recognizable FLAC marker followed by an invalid/truncated metadata header.
        let original = Data("fLaC\u{00} \u{00}".utf8)
        try original.write(to: source)

        do {
            try await TagWriterKit.write(
                url: source,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected malformed FLAC data to make the write fail.")
        } catch {
            // Expected: parser/writer rejects malformed FLAC.
        }

        XCTAssertEqual(
            try Data(contentsOf: source),
            original,
            "Failed writes must leave the source bytes unchanged."
        )

        let backup = URL(fileURLWithPath: source.path + "_original")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backup.path),
            "The original should be backed up before attempting to modify a supported format."
        )
        XCTAssertEqual(
            try Data(contentsOf: backup),
            original,
            "The backup must be an exact copy of the pre-write source."
        )
    }

    func testMalformedAIFFWriteKeepsSourceAndFirstBackupByteForByte() async throws {
        let source = temporaryDirectory.appendingPathComponent("broken.aiff")
        // FORM + a deliberately inconsistent declared size + AIFF form type.
        // The signature should dispatch to AIFFWriter; chunk parsing should fail.
        let original = Data([
            0x46, 0x4F, 0x52, 0x4D, // FORM
            0x00, 0x00, 0x00, 0x20, // declared size
            0x41, 0x49, 0x46, 0x46, // AIFF
            0x53, 0x53, 0x4E       // truncated "SSND" chunk id
        ])
        try original.write(to: source)

        do {
            try await TagWriterKit.write(
                url: source,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected malformed AIFF data to make the write fail.")
        } catch {
            // Expected: parser/writer rejects malformed AIFF.
        }

        XCTAssertEqual(
            try Data(contentsOf: source),
            original,
            "Failed writes must leave the source bytes unchanged."
        )

        let backup = URL(fileURLWithPath: source.path + "_original")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backup.path),
            "The original should be backed up before attempting to modify a supported format."
        )
        XCTAssertEqual(
            try Data(contentsOf: backup),
            original,
            "The backup must be an exact copy of the pre-write source."
        )
    }

    func testMalformedFLACStripKeepsSourceAndFirstBackupByteForByte() async throws {
        let source = temporaryDirectory.appendingPathComponent("broken-strip.flac")
        let original = Data("fLaC\u{00} \u{00}".utf8)
        try original.write(to: source)

        do {
            try await TagWriterKit.strip(url: source)
            XCTFail("Expected malformed FLAC data to make strip fail.")
        } catch {
            // Expected: parser/writer rejects malformed FLAC.
        }

        XCTAssertEqual(try Data(contentsOf: source), original)
        let backup = URL(fileURLWithPath: source.path + "_original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testExistingOriginalBackupIsNotReplacedWhenWriteFails() async throws {
        let source = temporaryDirectory.appendingPathComponent("broken.flac")
        let original = Data("fLaC\u{00} \u{00}".utf8)
        let firstBackup = Data("first original backup".utf8)
        try original.write(to: source)
        try firstBackup.write(to: URL(fileURLWithPath: source.path + "_original"))

        do {
            try await TagWriterKit.write(
                url: source,
                changes: TagChanges(title: "Must not be written")
            )
            XCTFail("Expected malformed FLAC data to make the write fail.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: source.path + "_original")),
            firstBackup,
            "A pre-existing original backup must never be overwritten."
        )
    }
}
*/
