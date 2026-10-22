import XCTest
import Foundation

final class TagWriterKitTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TandaComposerTagWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testEmptyChangesAreRejectedWithoutCreatingBackup() async throws {
        let source = temporaryDirectory.appendingPathComponent("track.flac")
        try Data("not actually flac".utf8).write(to: source)

        do {
            try await TagWriterKit.write(url: source, changes: TagChanges())
            XCTFail("Expected noChangesSpecified")
        } catch let error as TagWriteError {
            guard case .noChangesSpecified = error else {
                return XCTFail("Unexpected TagWriteError: \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path + "_original"))
    }

    func testUnsupportedFormatIsRejectedWithoutCreatingBackup() async throws {
        let source = temporaryDirectory.appendingPathComponent("notes.unsupported-test-format")
        try Data("plain text, not an audio file".utf8).write(to: source)

        do {
            try await TagWriterKit.write(url: source, changes: TagChanges(title: "Example"))
            XCTFail("Expected unsupportedFormat")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else {
                return XCTFail("Unexpected TagWriteError: \(error)")
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: source.path + "_original"),
            "An unsupported file must not produce a misleading original backup."
        )
    }
    
    
    func testWriteWithEmptyChangesThrowsAndPreservesOriginalFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-changes-\(UUID().uuidString).mp3")

        defer { try? FileManager.default.removeItem(at: url) }

        let original = Data([
            0xFF, 0xFB, 0x90, 0x64,
            0x11, 0x22, 0x33, 0x44
        ])
        try original.write(to: url)

        do {
            try await TagWriterKit.write(url: url, changes: TagChanges())
            XCTFail("Expected empty changes to be rejected.")
        } catch let error as TagWriteError {
            guard case .noChangesSpecified = error else {
                XCTFail("Expected noChangesSpecified, got \(error)")
                return
            }
        }

        XCTAssertEqual(
            try Data(contentsOf: url),
            original,
            "The file must remain unchanged when no changes are specified."
        )
    }

    
    func testUnsupportedFormatThrowsWithoutChangingOriginalFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("unsupported-\(UUID().uuidString).txt")

        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(
                at: url.appendingPathExtension("_original")
            )
        }

        let original = Data("This is not an audio file.".utf8)
        try original.write(to: url)

        do {
            try await TagWriterKit.write(
                url: url,
                changes: TagChanges(title: "New Title")
            )
            XCTFail("Expected unsupported format to be rejected.")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else {
                XCTFail("Expected unsupportedFormat, got \(error)")
                return
            }
        }

        XCTAssertEqual(
            try Data(contentsOf: url),
            original,
            "An unsupported file must remain unchanged."
        )
    }

    
    func testWritePreservesExistingOriginalBackup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TagWriterKit-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("unsupported.txt")
        let backupURL = URL(fileURLWithPath: url.path + "_original")

        let original = Data("Original file contents".utf8)
        let existingBackup = Data("First backup must be preserved".utf8)

        try original.write(to: url)
        try existingBackup.write(to: backupURL)

        do {
            try await TagWriterKit.write(
                url: url,
                changes: TagChanges(title: "New Title")
            )
            XCTFail("Expected unsupported format to be rejected.")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else {
                XCTFail("Expected unsupportedFormat, got \(error)")
                return
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(
            try Data(contentsOf: backupURL),
            existingBackup,
            "The existing original backup must not be overwritten."
        )
    }

    
    func testStripUnsupportedFormatThrowsAndPreservesOriginalFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("strip-unsupported-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("notes.txt")
        let original = Data("Do not modify this file".utf8)
        try original.write(to: url)

        do {
            try await TagWriterKit.strip(url: url)
            XCTFail("Expected unsupported format to be rejected.")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else {
                XCTFail("Expected unsupportedFormat, got \(error)")
                return
            }
        }

        XCTAssertEqual(
            try Data(contentsOf: url),
            original,
            "The original file must remain unchanged."
        )
    }

    
    func testStripMissingFileThrowsAndDoesNotCreateFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).mp3")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "The test file should not exist initially."
        )

        do {
            try await TagWriterKit.strip(url: url)
            XCTFail("Expected stripping a missing file to throw.")
        } catch {
            // Ein Fehler ist hier das erwartete Verhalten.
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "Stripping a missing file must not create it."
        )
    }

    
    func testWriteMissingFileThrowsAndDoesNotCreateFile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-write-\(UUID().uuidString).mp3")

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "The test file should not exist initially."
        )

        do {
            try await TagWriterKit.write(
                url: url,
                changes: TagChanges(title: "Test Title")
            )
            XCTFail("Expected writing to a missing file to throw.")
        } catch {
            // Der Fehler ist das erwartete Verhalten.
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "Writing tags must not create a missing source file."
        )
    }

    func testStripRejectsUnsupportedFormatWithoutCreatingBackup() async throws {
        let source = temporaryDirectory.appendingPathComponent("notes.unsupported-test-format")
        try Data("plain text, not an audio file".utf8).write(to: source)

        do {
            try await TagWriterKit.strip(url: source)
            XCTFail("Expected unsupportedFormat")
        } catch let error as TagWriteError {
            guard case .unsupportedFormat = error else {
                return XCTFail("Unexpected TagWriteError: \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path + "_original"))
    }

}
