import XCTest
import Foundation

final class FLACBlocksTests: XCTestCase {
    func testSerializeParseRoundTripPreservesBlocksAndAudio() throws {
        let blocks = [
            FLACBlock(type: FLACBlocks.streamInfo, data: Data([1, 2, 3, 4])),
            FLACBlock(type: FLACBlocks.vorbisComment, data: Data("comments".utf8)),
            FLACBlock(type: 5, data: Data([0xAA, 0xBB]))
        ]
        let audio = Data([0xFF, 0xF8, 0x10, 0x20, 0x30])
        let serialized = FLACBlocks.serialize(blocks: blocks, audioData: audio)
        let parsed = try FLACBlocks.parse(serialized)

        XCTAssertEqual(parsed.blocks.map(\.type), blocks.map(\.type))
        XCTAssertEqual(parsed.blocks.map(\.data), blocks.map(\.data))
        XCTAssertEqual(Data(serialized.suffix(from: parsed.audioOffset)), audio)
        XCTAssertEqual(serialized[4] & 0x80, 0)
        XCTAssertNotEqual(serialized[parsed.audioOffset - blocks.last!.data.count - 4] & 0x80, 0)
    }

    func testRejectsMissingFLACMarker() {
        XCTAssertThrowsError(try FLACBlocks.parse(Data("not flac".utf8))) { error in
            XCTAssertTrue(error is FLACParseError)
        }
    }

    func testRejectsTruncatedMetadataHeader() {
        XCTAssertThrowsError(try FLACBlocks.parse(Data("fLaC".utf8) + Data([0x80, 0x00]))) { error in
            XCTAssertTrue(error is FLACParseError)
        }
    }

    func testRejectsBlockWhoseDeclaredLengthExceedsInput() {
        let bytes = Data("fLaC".utf8) + Data([0x80, 0x00, 0x00, 0x10, 0x01, 0x02])
        XCTAssertThrowsError(try FLACBlocks.parse(bytes))
    }

    func testEmptyAudioPayloadIsPreserved() throws {
        let serialized = FLACBlocks.serialize(
            blocks: [FLACBlock(type: FLACBlocks.streamInfo, data: Data())],
            audioData: Data()
        )
        let parsed = try FLACBlocks.parse(serialized)
        XCTAssertEqual(parsed.audioOffset, serialized.count)
    }
}
