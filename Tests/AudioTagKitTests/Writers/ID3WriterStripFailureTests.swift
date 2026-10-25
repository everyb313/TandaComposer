import XCTest
import Foundation

/// `ID3Writer.strip` on an inconsistent ID3 header must fail and leave the
/// file exactly as it was. Today the computed audio start can lie beyond the
/// end of the audio (corrupt size) or inside the trailing ID3v1 tag, and
/// `strip` then cuts an empty or out-of-range slice: an emptied file, or a
/// crash.
///
/// NEEDS the guard in `ID3Writer.strip` (see README_TESTS.md).
final class ID3WriterStripFailureTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ID3WriterStripFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    private let sizeBeyondTheFile = Data([
        0x49, 0x44, 0x33,       // ID3
        0x04, 0x00, 0x00,       // v2.4, no flags
        0x00, 0x00, 0x00, 0x64, // declares 100 bytes
        0x11, 0x22, 0x33, 0x44
    ])

    private let invalidSyncsafeSize = Data([
        0x49, 0x44, 0x33,
        0x04, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x80, // high bit set: not a syncsafe integer
        0xFF, 0xFB, 0x90, 0x64
    ])

    /// The header declares 127 bytes, which fits the file, but reaches into
    /// the ID3v1 tag at the end.
    private let tagOverlappingTheID3v1Tail: Data = {
        var data = Data([
            0x49, 0x44, 0x33, 0x04, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x7F,
            0xFF, 0xFB, 0x90, 0x64
        ])
        data.append(Data("TAG".utf8))
        data.append(Data(repeating: 0x20, count: 125))
        return data
    }()

    private func assertStripFails(_ malformed: Data, name: String) async throws {
        let url = temporaryDirectory.appendingPathComponent(name)
        try malformed.write(to: url)

        do {
            try await ID3Writer.strip(url: url)
            XCTFail("Expected strip to reject the damaged ID3 header.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(
            try Data(contentsOf: url),
            malformed,
            "A failed strip must leave the file exactly as it was."
        )
    }

    func testStripRejectsATagSizeBeyondTheEndOfTheFile() async throws {
        try await assertStripFails(sizeBeyondTheFile, name: "beyond.mp3")
    }

    func testStripRejectsAnInvalidSyncsafeSize() async throws {
        try await assertStripFails(invalidSyncsafeSize, name: "syncsafe.mp3")
    }

    func testStripRejectsATagThatReachesIntoTheID3v1Tail() async throws {
        try await assertStripFails(tagOverlappingTheID3v1Tail, name: "with-v1.mp3")
    }

    func testPublicStripKeepsSourceAndFirstBackupByteForByte() async throws {
        let url = temporaryDirectory.appendingPathComponent("public.mp3")
        try sizeBeyondTheFile.write(to: url)

        do {
            try await TagWriterKit.strip(url: url)
            XCTFail("Expected strip to reject the damaged ID3 header.")
        } catch {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: url), sizeBeyondTheFile)
        let backup = URL(fileURLWithPath: url.path + "_original")
        XCTAssertEqual(try Data(contentsOf: backup), sizeBeyondTheFile)
    }
}
