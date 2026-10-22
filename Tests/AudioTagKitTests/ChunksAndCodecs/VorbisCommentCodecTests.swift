import XCTest
import Foundation

final class VorbisCommentCodecTests: XCTestCase {
    func testEncodeDecodeRoundTripsUnicodeAndEqualsInValue() {
        let input = [
            "TITLE": "東京 – Tango",
            "ARTIST": "Artist = Ensemble",
            "COMMENT": "Line one\nLine two"
        ]
        let decoded = VorbisCommentCodec.decode(VorbisCommentCodec.encode(input))
        XCTAssertEqual(decoded, input)
    }

    func testKeysAreDecodedCaseInsensitively() {
        var block = Data()
        appendLE(1, to: &block)
        block.append(contentsOf: "v".utf8)
        appendLE(2, to: &block)
        appendEntry("title=First", to: &block)
        appendEntry("ARTIST=Second", to: &block)

        let decoded = VorbisCommentCodec.decode(block)
        XCTAssertEqual(decoded["TITLE"], "First")
        XCTAssertEqual(decoded["ARTIST"], "Second")
    }

    func testMalformedAndTruncatedBlocksReturnPartialOrEmptyResult() {
        XCTAssertTrue(VorbisCommentCodec.decode(Data()).isEmpty)
        XCTAssertTrue(VorbisCommentCodec.decode(Data([0xFF, 0xFF, 0xFF, 0x7F])).isEmpty)

        var truncated = Data()
        appendLE(1, to: &truncated)
        truncated.append(0x76) // vendor
        appendLE(1, to: &truncated) // one comment follows
        appendLE(20, to: &truncated) // but its payload is absent
        XCTAssertTrue(VorbisCommentCodec.decode(truncated).isEmpty)
    }

    func testEntriesWithoutEqualsAreIgnored() {
        var block = Data()
        appendLE(1, to: &block)
        block.append(0x76)
        appendLE(2, to: &block)
        appendEntry("TITLE=Valid", to: &block)
        appendEntry("INVALIDENTRY", to: &block)

        XCTAssertEqual(VorbisCommentCodec.decode(block), ["TITLE": "Valid"])
    }

    private func appendEntry(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendLE(bytes.count, to: &data)
        data.append(bytes)
    }

    private func appendLE(_ value: Int, to data: inout Data) {
        let v = UInt32(value)
        data.append(contentsOf: [
            UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
            UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)
        ])
    }
}
