import XCTest
import Foundation

final class FLACWriterTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLACWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testWritesTitleAndArtistAndPreservesAudioPayload() async throws {
        let url = try makeFLACFile(audioPayload: Data([0xFF, 0xF8, 0xAA, 0xBB, 0x10, 0x20]))
        let originalAudio = try audioPayload(in: Data(contentsOf: url))

        try await FLACWriter.write(url: url, changes: TagChanges(title: "Test Title", artist: "Test Artist"))

        let writtenData = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(writtenData)
        let commentBlock = try XCTUnwrap(parsed.blocks.first(where: { $0.type == FLACBlocks.vorbisComment }))
        let comments = VorbisCommentCodec.decode(commentBlock.data)

        XCTAssertEqual(comments["TITLE"], "Test Title")
        XCTAssertEqual(comments["ARTIST"], "Test Artist")
        XCTAssertEqual(try audioPayload(in: writtenData), originalAudio)
    }

    func testUpdatesExistingCommentsAndPreservesUnchangedFields() async throws {
        let url = try makeFLACFile(audioPayload: Data([0x11, 0x22, 0x33]), comments: ["TITLE": "Old title", "ALBUM": "Keep this"])

        try await FLACWriter.write(url: url, changes: TagChanges(title: "New title"))

        let parsed = try FLACBlocks.parse(Data(contentsOf: url))
        let block = try XCTUnwrap(parsed.blocks.first(where: { $0.type == FLACBlocks.vorbisComment }))
        let comments = VorbisCommentCodec.decode(block.data)
        XCTAssertEqual(comments["TITLE"], "New title")
        XCTAssertEqual(comments["ALBUM"], "Keep this")
    }

    func testStripRemovesVorbisCommentsAndPicturesButPreservesAudio() async throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let url = try makeFLACFile(audioPayload: payload, comments: ["TITLE": "Private title"], includePicture: true)

        try await FLACWriter.strip(url: url)

        let result = try Data(contentsOf: url)
        let parsed = try FLACBlocks.parse(result)
        XCTAssertFalse(parsed.blocks.contains(where: { $0.type == FLACBlocks.vorbisComment }))
        XCTAssertFalse(parsed.blocks.contains(where: { $0.type == FLACBlocks.picture }))
        XCTAssertEqual(try audioPayload(in: result), payload)
    }

    func testMalformedFLACThrowsAndLeavesOriginalUnchanged() async throws {
        let url = temporaryDirectory.appendingPathComponent("broken.flac")
        let original = Data("fLaC\u{00} \u{00}".utf8)
        try original.write(to: url)

        do {
            try await FLACWriter.write(url: url, changes: TagChanges(title: "Should fail"))
            XCTFail("Expected malformed FLAC input to throw")
        } catch {
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    // MARK: - Fixture helpers

    private func makeFLACFile(
        audioPayload: Data,
        comments: [String: String]? = nil,
        includePicture: Bool = false
    ) throws -> URL {
        var blocks: [FLACBlock] = [FLACBlock(type: FLACBlocks.streamInfo, data: Data(repeating: 0, count: 34))]
        if let comments {
            blocks.append(FLACBlock(type: FLACBlocks.vorbisComment, data: VorbisCommentCodec.encode(comments)))
        }
        if includePicture {
            blocks.append(FLACBlock(type: FLACBlocks.picture, data: Data([0, 0, 0, 0])))
        }
        let data = FLACBlocks.serialize(blocks: blocks, audioData: audioPayload)
        let url = temporaryDirectory.appendingPathComponent("fixture-\(UUID().uuidString).flac")
        try data.write(to: url)
        return url
    }

    private func audioPayload(in data: Data) throws -> Data {
        let parsed = try FLACBlocks.parse(data)
        return data.subdata(in: parsed.audioOffset..<data.endIndex)
    }
}
