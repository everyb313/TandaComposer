import XCTest
import Foundation

final class AudioMetadataKitReaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioMetadataKitReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testDispatchesFLACToFLACReader() async throws {
        let comments = VorbisCommentCodec.encode(["TITLE": "Dispatch title"])
        let data = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34)),
                FLACBlock(type: FLACBlocks.vorbisComment, data: comments)
            ],
            audioData: Data([0xFF, 0xF8, 0x00])
        )
        let url = temporaryDirectory.appendingPathComponent("dispatch.flac")
        try data.write(to: url)

        let metadata = try await AudioMetadataKit.read(url: url)
        let tags = try XCTUnwrap(metadata["vorbisComments"] as? [String: String])

        XCTAssertEqual(metadata["format"] as? String, "FLAC")
        XCTAssertEqual(tags["TITLE"], "Dispatch title")
    }

    func testDispatchesAIFFToAIFFReader() async throws {
        let titleFrame = ID3FrameCodec.textFrame("TIT2", "AIFF dispatch title")
        let id3Data = ID3FrameCodec.header(bodySize: titleFrame.count) + titleFrame
        let data = AIFFChunks.serialize(
            formType: "AIFF",
            chunks: [
                AIFFChunk(id: "COMM", data: Data(repeating: 0, count: 18)),
                AIFFChunk(id: "ID3 ", data: id3Data),
                AIFFChunk(id: "SSND", data: Data(repeating: 0, count: 8))
            ]
        )
        let url = temporaryDirectory.appendingPathComponent("dispatch.aiff")
        try data.write(to: url)

        let metadata = try await AudioMetadataKit.read(url: url)
        let common = try XCTUnwrap(metadata["common"] as? [String: Any])

        XCTAssertEqual(metadata["format"] as? String, "AIFF")
        XCTAssertEqual(common["title"] as? String, "AIFF dispatch title")
    }

    func testMissingFLACFileFailsWithoutCreatingIt() async throws {
        let url = temporaryDirectory.appendingPathComponent("missing.flac")

        do {
            _ = try await AudioMetadataKit.read(url: url)
            XCTFail("Reading a missing FLAC file should throw.")
        } catch {
            // Expected: the reader cannot load a file that does not exist.
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
