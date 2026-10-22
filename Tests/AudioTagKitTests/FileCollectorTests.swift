import XCTest
import Foundation

final class FileCollectorP2Tests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioTagKitFileCollector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// macOS may expose the temporary directory through /var or /private/var.
    /// Resolve symlinks before comparing paths so tests compare file identity,
    /// not the spelling of the same filesystem path.
    private func normalizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    @discardableResult
    private func makeFile(_ relativePath: String, contents: String = "test") throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testNonRecursiveCollectionIncludesOnlyImmediateSupportedAudioFiles() throws {
        let top = try makeFile("b.FLAC")
        _ = try makeFile("notes.txt")
        _ = try makeFile("sub/nested.mp3")
        let results = try FileCollector.collect(from: [root.path], recursive: false)
        XCTAssertEqual(results.map { normalizedPath(URL(fileURLWithPath: $0.path)) }, [normalizedPath(top)])
    }

    func testRecursiveCollectionIncludesNestedSupportedAudioFiles() throws {
        let top = try makeFile("top.aiff")
        let nested = try makeFile("sub/nested.Mp3")
        _ = try makeFile("sub/document.pdf")
        let results = try FileCollector.collect(from: [root.path], recursive: true)
        XCTAssertEqual(results.map { normalizedPath(URL(fileURLWithPath: $0.path)) }, [normalizedPath(nested), normalizedPath(top)].sorted())
    }

    func testDuplicatePathsAreDeduplicatedAndResultsSorted() throws {
        let a = try makeFile("a.flac")
        let b = try makeFile("b.mp3")
        let results = try FileCollector.collect(from: [b.path, a.path, a.path], recursive: false)
        XCTAssertEqual(results.map { normalizedPath(URL(fileURLWithPath: $0.path)) }, [normalizedPath(a), normalizedPath(b)].sorted())
    }

    func testMissingPathsAreSkipped() throws {
        let existing = try makeFile("ok.flac")
        let missing = root.appendingPathComponent("missing.mp3")
        let results = try FileCollector.collect(from: [missing.path, existing.path], recursive: true)
        XCTAssertEqual(results.map { normalizedPath(URL(fileURLWithPath: $0.path)) }, [normalizedPath(existing)])
    }

    func testHiddenFilesAreSkippedWhenCollectingDirectory() throws {
        let visible = try makeFile("visible.flac")
        _ = try makeFile(".hidden.flac")
        let results = try FileCollector.collect(from: [root.path], recursive: true)
        XCTAssertEqual(results.map { normalizedPath(URL(fileURLWithPath: $0.path)) }, [normalizedPath(visible)])
    }
}
