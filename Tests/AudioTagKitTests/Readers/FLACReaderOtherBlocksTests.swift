import XCTest
import Foundation

/// FLAC files carry more block types than the reader cares about (PADDING,
/// APPLICATION, SEEKTABLE, CUESHEET). They must not disturb reading.
final class FLACReaderOtherBlocksTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLACReaderOtherBlocksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testPaddingApplicationSeekTableAndCueSheetBlocksAreIgnored() async throws {
        let file = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34)),
                FLACBlock(type: 1, data: Data(repeating: 0, count: 64)),   // PADDING
                FLACBlock(type: 2, data: Data(repeating: 7, count: 8)),    // APPLICATION
                FLACBlock(type: 3, data: Data(repeating: 0, count: 18)),   // SEEKTABLE
                FLACBlock(type: 5, data: Data(repeating: 0, count: 396)),  // CUESHEET
                FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(["TITLE": "Poema"]))
            ],
            audioData: Data([0xFF, 0xF8, 0x01])
        )
        let url = temporaryDirectory.appendingPathComponent("other-blocks.flac")
        try file.write(to: url)

        let metadata = try await FLACReader.read(url: url)

        let comments = try XCTUnwrap(metadata["vorbisComments"] as? [String: String])
        XCTAssertEqual(comments["TITLE"], "Poema")
        XCTAssertNil(metadata["hasArtwork"])
        XCTAssertEqual(metadata["format"] as? String, "FLAC")
    }
}
