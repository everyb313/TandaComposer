import XCTest
import Foundation

final class ID3FrameCodecTests: XCTestCase {
    func testTextFrameRoundTripsUnicode() throws {
        let value = "Björk – 東京 🎵"
        let tag = ID3FrameCodec.header(bodySize: ID3FrameCodec.textFrame("TIT2", value).count)
            + ID3FrameCodec.textFrame("TIT2", value)

        let frame = try XCTUnwrap(ID3FrameCodec.parseTag(tag).first { $0.id == "TIT2" })
        XCTAssertEqual(ID3FrameCodec.decodeTextValue(frame.content), value)
    }

    func testCommentFrameRoundTripsUnicode() throws {
        let value = "Grüße, 東京, 🎶"
        let frameData = ID3FrameCodec.commentFrame(value)
        let tag = ID3FrameCodec.header(bodySize: frameData.count) + frameData
        let frame = try XCTUnwrap(ID3FrameCodec.parseTag(tag).first { $0.id == "COMM" })
        XCTAssertEqual(ID3FrameCodec.decodeCommentValue(frame.content), value)
    }

    func testRejectsDataWithoutID3Header() {
        XCTAssertTrue(ID3FrameCodec.parseTag(Data([0x00, 0x01, 0x02])).isEmpty)
        XCTAssertTrue(ID3FrameCodec.parseTag(Data("NOTID3____".utf8)).isEmpty)
    }

    func testIgnoresTruncatedFrameInsteadOfReadingPastEnd() {
        // Valid ID3 header whose declared body contains an incomplete frame header.
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [0x04, 0x00, 0x00])
        tag.append(ID3FrameCodec.syncsafeEncode(5))
        tag.append(contentsOf: [0x54, 0x49, 0x54, 0x32, 0x00])
        XCTAssertTrue(ID3FrameCodec.parseTag(tag).isEmpty)
    }

    func testSyncsafeSizeRoundTripsRepresentativeValues() {
        for value in [0, 1, 127, 128, 16_383, 16_384, 1_000_000] {
            XCTAssertEqual(ID3FrameCodec.syncsafeDecode(ID3FrameCodec.syncsafeEncode(value)), value)
        }
    }

    func testPictureFrameRejectsTruncatedPayload() {
        XCTAssertNil(ID3FrameCodec.decodePictureFrame(Data([0x00, 0x01])))
    }
}
