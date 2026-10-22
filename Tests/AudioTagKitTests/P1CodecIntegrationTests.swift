import XCTest
import Foundation

/// Cross-codec regression tests for the low-level formats used by the
/// MP3/AIFF and FLAC readers/writers. These tests do not exercise MP4/M4A.
final class P1CodecIntegrationTests: XCTestCase {
    func testID3TagCanBeParsedAfterSerializationAndKeepsUnknownFrames() throws {
        let title = ID3FrameCodec.textFrame("TIT2", "Tango – 東京")
        let unknown = ID3FrameCodec.frame(id: "TXXX", content: Data([0x00, 0x61, 0x62]))
        let body = title + unknown
        let tag = ID3FrameCodec.header(bodySize: body.count) + body

        let parsed = ID3FrameCodec.parseTag(tag)
        XCTAssertEqual(parsed.map(\.id), ["TIT2", "TXXX"])
        XCTAssertEqual(ID3FrameCodec.decodeTextValue(try XCTUnwrap(parsed.first { $0.id == "TIT2" }).content), "Tango – 東京")
        XCTAssertEqual(try XCTUnwrap(parsed.first { $0.id == "TXXX" }).content, Data([0x00, 0x61, 0x62]))
    }

    func testFLACCommentBlockRoundTripsThroughBlockContainer() throws {
        let comments = ["TITLE": "Song", "ARTIST": "Band"]
        let commentBlock = VorbisCommentCodec.encode(comments)
        let audio = Data([0xFF, 0xF8, 0x11, 0x22])
        let serialized = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data([1, 2, 3])),
                FLACBlock(type: FLACBlocks.vorbisComment, data: commentBlock)
            ],
            audioData: audio
        )

        let parsed = try FLACBlocks.parse(serialized)
        let block = try XCTUnwrap(parsed.blocks.first { $0.type == FLACBlocks.vorbisComment })
        XCTAssertEqual(VorbisCommentCodec.decode(block.data), comments)
        XCTAssertEqual(Data(serialized.suffix(from: parsed.audioOffset)), audio)
    }

    func testAIFFEmbeddedID3ChunkRoundTripsThroughBothCodecs() throws {
        let frame = ID3FrameCodec.textFrame("TIT2", "Milonga")
        let tag = ID3FrameCodec.header(bodySize: frame.count) + frame
        let aiff = AIFFChunks.serialize(formType: "AIFF", chunks: [
            AIFFChunk(id: "COMM", data: Data([0, 1, 0, 2])),
            AIFFChunk(id: "ID3 ", data: tag),
            AIFFChunk(id: "SSND", data: Data([0x10, 0x20, 0x30]))
        ])

        let parsed = try AIFFChunks.parse(aiff)
        let id3 = try XCTUnwrap(parsed.chunks.first { $0.id == "ID3 " })
        let frames = ID3FrameCodec.parseTag(id3.data)
        XCTAssertEqual(ID3FrameCodec.decodeTextValue(try XCTUnwrap(frames.first { $0.id == "TIT2" }).content), "Milonga")
        XCTAssertEqual(try XCTUnwrap(parsed.chunks.first { $0.id == "SSND" }).data, Data([0x10, 0x20, 0x30]))
    }
}
