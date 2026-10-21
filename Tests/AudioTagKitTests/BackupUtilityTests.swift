
import XCTest
import Foundation

final class BackupUtilityTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TandaComposerTests-\(UUID().uuidString)",
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

    func testCreatesBackupWithOriginalFilenameAndIdenticalBytes() throws {
        let source = temporaryDirectory.appendingPathComponent("track.flac")
        let original = Data([0x66, 0x4C, 0x61, 0x43, 0x00, 0x01, 0x02])
        try original.write(to: source)

        let backup = try BackupUtility.backupOriginalIfNeeded(for: source)

        XCTAssertEqual(backup.path, source.path + "_original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testExistingBackupIsNotOverwritten() throws {
        let source = temporaryDirectory.appendingPathComponent("track.mp3")
        let backup = URL(fileURLWithPath: source.path + "_original")

        try Data([0x01, 0x02]).write(to: source)

        let existingBackup = Data([0xAA, 0xBB, 0xCC])
        try existingBackup.write(to: backup)

        let returnedURL = try BackupUtility.backupOriginalIfNeeded(for: source)

        XCTAssertEqual(
            returnedURL.standardizedFileURL.path,
            backup.standardizedFileURL.path
        )
        XCTAssertEqual(try Data(contentsOf: backup), existingBackup)
    }

    func testRepeatedCallKeepsFirstOriginalAfterSourceChanges() throws {
        let source = temporaryDirectory.appendingPathComponent("track.aiff")

        let firstVersion = Data([0x46, 0x4F, 0x52, 0x4D, 0x01])
        let modifiedVersion = Data([0x46, 0x4F, 0x52, 0x4D, 0x02, 0x03])

        try firstVersion.write(to: source)

        let firstBackupURL = try BackupUtility.backupOriginalIfNeeded(for: source)

        try modifiedVersion.write(to: source)

        let secondBackupURL = try BackupUtility.backupOriginalIfNeeded(for: source)

        XCTAssertEqual(
            secondBackupURL.standardizedFileURL.path,
            firstBackupURL.standardizedFileURL.path
        )

        XCTAssertEqual(
            try Data(contentsOf: secondBackupURL),
            firstVersion,
            "The first backup must remain the original version."
        )

        XCTAssertEqual(
            try Data(contentsOf: source),
            modifiedVersion
        )
    }

    func testMissingSourceThrowsSourceNotFound() {
        let source = temporaryDirectory.appendingPathComponent("missing.flac")

        XCTAssertThrowsError(
            try BackupUtility.backupOriginalIfNeeded(for: source)
        ) { error in
            guard let backupError = error as? BackupError,
                  case .sourceNotFound = backupError else {
                return XCTFail("Expected sourceNotFound, got: \(error)")
            }
        }
    }

    
    func testExistingBackupDirectoryDoesNotModifySourceFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-directory-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("song.mp3")
        let backupURL = URL(fileURLWithPath: sourceURL.path + "_original")

        let original = Data("Original audio contents".utf8)
        try original.write(to: sourceURL)

        try FileManager.default.createDirectory(
            at: backupURL,
            withIntermediateDirectories: true
        )

        let returnedURL = try BackupUtility.backupOriginalIfNeeded(for: sourceURL)
        XCTAssertEqual(
            returnedURL.standardizedFileURL.path,
            backupURL.standardizedFileURL.path
        )
        //XCTAssertEqual(returnedURL, backupURL)
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: backupURL.path),
            "The existing backup directory must not be overwritten."
        )
    }

    func testExistingDirectoryAtBackupPathIsNotOverwritten() throws {
        let source = temporaryDirectory.appendingPathComponent("track.flac")
        let original = Data([0x66, 0x4C, 0x61, 0x43, 0x10, 0x20, 0x30])

        try original.write(to: source)

        let backupURL = URL(fileURLWithPath: source.path + "_original")

        try FileManager.default.createDirectory(
            at: backupURL,
            withIntermediateDirectories: false
        )

        // The current implementation treats any existing path as a backup.
        let returnedURL = try BackupUtility.backupOriginalIfNeeded(for: source)

        XCTAssertEqual(
            returnedURL.standardizedFileURL.path,
            backupURL.standardizedFileURL.path
        )

        var isDirectory: ObjCBool = false

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: backupURL.path,
                isDirectory: &isDirectory
            )
        )

        XCTAssertTrue(
            isDirectory.boolValue,
            "The existing backup path should still be a directory."
        )

        XCTAssertEqual(
            try Data(contentsOf: source),
            original,
            "The source file must remain unchanged."
        )
    }
}

