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
