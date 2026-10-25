import XCTest
import Foundation

/// The decoding side of `ID3FrameCodec`: text encodings, comment frames,
/// user-text frames, picture frames and the v2.3 / v2.4 frame size rules.
final class ID3FrameCodecDecodingTests: XCTestCase {

    private func bytes(_ values: UInt8...) -> Data { Data(values) }
    private func text(_ value: String) -> Data { Data(value.utf8) }

    // MARK: - decodeTextValue

    func testEmptyContentDecodesToAnEmptyString() {
        XCTAssertEqual(ID3FrameCodec.decodeTextValue(Data()), "")
    }

    func testLatin1IsNotReadAsUTF8() {
        let content = bytes(0x00, 0x43, 0x61, 0x66, 0xE9)

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "Caf\u{00E9}")
    }

    func testLatin1TrimsTrailingNulBytes() {
        let content = bytes(0x00) + text("abc") + bytes(0x00)

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "abc")
    }

    func testUTF16WithLittleEndianBOM() {
        let content = bytes(0x01, 0xFF, 0xFE, 0x41, 0x00, 0x00, 0x00)

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "A")
    }

    func testUTF16WithBigEndianBOM() {
        let content = bytes(0x01, 0xFE, 0xFF, 0x00, 0x41)

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "A")
    }

    func testUTF16BigEndianWithoutBOM() {
        let content = bytes(0x02, 0x00, 0x41)

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "A")
    }

    func testUTF8IncludingAccentsAndTrailingNul() {
        let content = bytes(0x03) + text("\u{00D1}and\u{00FA}") + bytes(0x00)

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "\u{00D1}and\u{00FA}")
    }

    func testAnUnknownEncodingByteIsTreatedAsUTF8() {
        let content = bytes(0x09) + text("Tango")

        XCTAssertEqual(ID3FrameCodec.decodeTextValue(content), "Tango")
    }

    // MARK: - decodeCommentFrame

    func testCommentFrameShorterThanItsHeaderIsEmpty() {
        let result = ID3FrameCodec.decodeCommentFrame(bytes(0x00, 0x65, 0x6E, 0x67))

        XCTAssertEqual(result.description, "")
        XCTAssertEqual(result.value, "")
    }

    func testLatin1CommentWithADescription() {
        let content = bytes(0x00) + text("eng") + text("desc") + bytes(0x00) + text("value")

        let result = ID3FrameCodec.decodeCommentFrame(content)

        XCTAssertEqual(result.description, "desc")
        XCTAssertEqual(result.value, "value")
    }

    func testCommentWithAnEmptyDescription() {
        let content = bytes(0x00) + text("eng") + bytes(0x00) + text("text")

        let result = ID3FrameCodec.decodeCommentFrame(content)

        XCTAssertEqual(result.description, "")
        XCTAssertEqual(result.value, "text")
    }

    func testUTF16CommentWithADescription() {
        let content = bytes(0x01) + text("eng")
            + bytes(0xFF, 0xFE, 0x64, 0x00) + bytes(0x00, 0x00)
            + bytes(0xFF, 0xFE, 0x76, 0x00)

        let result = ID3FrameCodec.decodeCommentFrame(content)

        XCTAssertEqual(result.description, "d")
        XCTAssertEqual(result.value, "v")
    }

    func testUTF8CommentWithAccents() {
        let content = bytes(0x03) + text("eng") + text("d\u{00E9}") + bytes(0x00) + text("v\u{00E9}")

        let result = ID3FrameCodec.decodeCommentFrame(content)

        XCTAssertEqual(result.description, "d\u{00E9}")
        XCTAssertEqual(result.value, "v\u{00E9}")
    }

    func testCommentWithoutADescriptionTerminatorHasNoValue() {
        let content = bytes(0x00) + text("eng") + text("abc")

        let result = ID3FrameCodec.decodeCommentFrame(content)

        XCTAssertEqual(result.description, "abc")
        XCTAssertEqual(result.value, "")
    }

    func testDecodeCommentValueReturnsJustTheValue() {
        let content = bytes(0x00) + text("eng") + text("desc") + bytes(0x00) + text("value")

        XCTAssertEqual(ID3FrameCodec.decodeCommentValue(content), "value")
    }

    // MARK: - decodeUserTextFrame

    func testEmptyUserTextFrame() {
        let result = ID3FrameCodec.decodeUserTextFrame(Data())

        XCTAssertEqual(result.description, "")
        XCTAssertEqual(result.value, "")
    }

    func testLatin1UserTextFrame() {
        let content = bytes(0x00) + text("REPLAYGAIN_TRACK_GAIN") + bytes(0x00) + text("-6.2 dB")

        let result = ID3FrameCodec.decodeUserTextFrame(content)

        XCTAssertEqual(result.description, "REPLAYGAIN_TRACK_GAIN")
        XCTAssertEqual(result.value, "-6.2 dB")
    }

    func testUTF16UserTextFrame() {
        let content = bytes(0x01)
            + bytes(0xFF, 0xFE, 0x41, 0x00) + bytes(0x00, 0x00)
            + bytes(0xFF, 0xFE, 0x42, 0x00)

        let result = ID3FrameCodec.decodeUserTextFrame(content)

        XCTAssertEqual(result.description, "A")
        XCTAssertEqual(result.value, "B")
    }

    func testUserTextFrameWithoutATerminatorHasNoValue() {
        let result = ID3FrameCodec.decodeUserTextFrame(bytes(0x00) + text("desc"))

        XCTAssertEqual(result.description, "desc")
        XCTAssertEqual(result.value, "")
    }

    func testUserTextFrameWithAnEmptyDescription() {
        let result = ID3FrameCodec.decodeUserTextFrame(bytes(0x00, 0x00) + text("v"))

        XCTAssertEqual(result.description, "")
        XCTAssertEqual(result.value, "v")
    }

    // MARK: - decodePictureFrame

    func testPictureFrameWithALatin1Description() throws {
        let content = bytes(0x00) + text("image/png") + bytes(0x00, 0x03)
            + text("cover") + bytes(0x00) + bytes(1, 2, 3)

        let picture = try XCTUnwrap(ID3FrameCodec.decodePictureFrame(content))

        XCTAssertEqual(picture.mime, "image/png")
        XCTAssertEqual(picture.data, bytes(1, 2, 3))
    }

    func testPictureFrameWithAUTF16Description() throws {
        let content = bytes(0x01) + text("image/png") + bytes(0x00, 0x03)
            + bytes(0xFF, 0xFE, 0x63, 0x00) + bytes(0x00, 0x00) + bytes(9, 8, 7)

        let picture = try XCTUnwrap(ID3FrameCodec.decodePictureFrame(content))

        XCTAssertEqual(picture.mime, "image/png")
        XCTAssertEqual(picture.data, bytes(9, 8, 7))
    }

    func testPictureFrameWithAnUnterminatedUTF16DescriptionHasNoImageData() throws {
        let content = bytes(0x01) + text("image/png") + bytes(0x00, 0x03)
            + bytes(0xFF, 0xFE, 0x63, 0x00)

        let picture = try XCTUnwrap(ID3FrameCodec.decodePictureFrame(content))

        XCTAssertEqual(picture.mime, "image/png")
        XCTAssertTrue(picture.data.isEmpty)
    }

    func testPictureFrameThatCannotBeDecodedIsNil() {
        XCTAssertNil(ID3FrameCodec.decodePictureFrame(Data()), "empty")
        XCTAssertNil(
            ID3FrameCodec.decodePictureFrame(bytes(0x00) + text("image/png")),
            "MIME type without its terminator"
        )
        XCTAssertNil(
            ID3FrameCodec.decodePictureFrame(bytes(0x00) + text("m") + bytes(0x00)),
            "no picture type byte"
        )
        XCTAssertNil(
            ID3FrameCodec.decodePictureFrame(bytes(0x00) + text("m") + bytes(0x00, 0x03) + text("desc")),
            "description without its terminator"
        )
    }

    // MARK: - Frame sizes (v2.3 plain, v2.4 syncsafe)

    private func tag(version: UInt8, body: Data, declaredBodySize: Int? = nil) -> Data {
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [version, 0x00, 0x00])
        tag.append(ID3FrameCodec.syncsafeEncode(declaredBodySize ?? body.count))
        tag.append(body)
        return tag
    }

    func testVersion23FrameSizesArePlainIntegers() {
        // 128 as a plain integer is 00 00 00 80, which is not a valid syncsafe
        // integer (it would decode as 0).
        var frame = Data("TIT2".utf8)
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x80, 0x00, 0x00])
        frame.append(Data([0x00]) + Data(repeating: 0x41, count: 127))

        let frames = ID3FrameCodec.parseTag(tag(version: 3, body: frame))

        XCTAssertEqual(frames.map(\.id), ["TIT2"])
        XCTAssertEqual(frames.first?.content.count, 128)
    }

    func testVersion24FrameSizesAreSyncsafe() {
        let frame = ID3FrameCodec.textFrame("TIT2", "Title")

        let frames = ID3FrameCodec.parseTag(tag(version: 4, body: frame))

        XCTAssertEqual(frames.map(\.id), ["TIT2"])
        XCTAssertEqual(ID3FrameCodec.decodeTextValue(frames[0].content), "Title")
    }

    func testPaddingAfterTheLastFrameEndsParsing() {
        let body = ID3FrameCodec.textFrame("TIT2", "Title") + Data(repeating: 0x00, count: 20)

        let frames = ID3FrameCodec.parseTag(tag(version: 4, body: body))

        XCTAssertEqual(frames.map(\.id), ["TIT2"])
    }

    func testADeclaredTagSizeBeyondTheDataStillYieldsTheFramesThatAreThere() {
        let body = ID3FrameCodec.textFrame("TIT2", "Title")

        let frames = ID3FrameCodec.parseTag(tag(version: 4, body: body, declaredBodySize: 1000))

        XCTAssertEqual(frames.map(\.id), ["TIT2"])
    }

    func testParseFramesCanBeToldTheSizeEncoding() {
        var frame = Data("TIT2".utf8)
        frame.append(contentsOf: [0x00, 0x00, 0x00, 0x03, 0x00, 0x00])
        frame.append(contentsOf: [0x00, 0x41, 0x42])

        let plain = ID3FrameCodec.parseFrames(frame, sizesAreSyncsafe: false)
        let syncsafe = ID3FrameCodec.parseFrames(frame, sizesAreSyncsafe: true)

        XCTAssertEqual(plain.first?.content.count, 3)
        XCTAssertEqual(syncsafe.first?.content.count, 3, "values below 128 are identical in both encodings")
    }

    func testTheFrameIDOfARawFrame() {
        XCTAssertEqual(ID3FrameCodec.frameID(of: ID3FrameCodec.textFrame("TPE1", "x")), "TPE1")
        XCTAssertNil(ID3FrameCodec.frameID(of: Data([0x54, 0x49, 0x54])))
    }
}
