import XCTest
import Foundation

/// If the "_original" copy cannot be made, the operation must stop with a
/// clear error before anything is modified.
final class BackupUtilityFailureTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupUtilityFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            // Make sure the folder can be removed even if a test left it read-only.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryDirectory.path)
            for case let url as URL in FileManager.default.enumerator(at: temporaryDirectory, includingPropertiesForKeys: nil) ?? NSEnumerator() {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testACopyThatFailsIsReportedAsCopyFailedAndLeavesTheSourceAlone() throws {
        try XCTSkipIf(getuid() == 0, "permissions do not apply to root")

        let folder = temporaryDirectory.appendingPathComponent("readonly", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("track.flac")
        let original = Data([1, 2, 3, 4])
        try original.write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)

        XCTAssertThrowsError(try BackupUtility.backupOriginalIfNeeded(for: source)) { error in
            guard case BackupError.copyFailed = error else {
                return XCTFail("expected .copyFailed, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path + "_original"))
    }
}
