import XCTest
import Foundation

/// `AIFFChunks.parse` has two modes:
///
/// - strict (default, used before WRITING): any inconsistency is an error, so
///   a damaged file is never rewritten into a valid-looking one;
/// - lenient (used for READING): reads everything that is intact, so a wrong
///   FORM size, trailing bytes, a missing final pad byte or a cut-off last
///   chunk do not make the whole file unreadable.
///
/// NEEDS the `lenient:` parameter (see README_TESTS.md).
final class AIFFChunksLenientTests: XCTestCase {

    private let first = AIFFChunk(id: "AAAA", data: Data([1, 2, 3, 4]))
    private let second = AIFFChunk(id: "BBBB", data: Data([5, 6]))

    private var valid: Data {
        AIFFChunks.serialize(formType: "AIFF", chunks: [first, second])
    }

    private func settingFormSize(_ size: Int, in data: Data) -> Data {
        let value = UInt32(truncatingIfNeeded: size)
        var copy = data
        copy.replaceSubrange(4..<8, with: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)
        ])
        return copy
    }

    /// Re-declares the FORM size so that it matches the actual length.
    private func consistent(_ data: Data) -> Data {
        settingFormSize(data.count - 8, in: data)
    }

    private func lenientIDs(_ data: Data) throws -> [String] {
        try AIFFChunks.parse(data, lenient: true).chunks.map(\.id)
    }

    private func assertStrictRejects(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try AIFFChunks.parse(data), file: file, line: line) { error in
            guard case AIFFParseError.truncated = error else {
                return XCTFail("expected .truncated, got \(error)", file: file, line: line)
            }
        }
    }

    // MARK: - Consistent files

    func testAValidFileParsesTheSameInBothModes() throws {
        let strict = try AIFFChunks.parse(valid)
        let lenient = try AIFFChunks.parse(valid, lenient: true)

        XCTAssertEqual(strict.formType, "AIFF")
        XCTAssertEqual(lenient.formType, "AIFF")
        XCTAssertEqual(strict.chunks.map(\.id), ["AAAA", "BBBB"])
        XCTAssertEqual(lenient.chunks.map(\.id), ["AAAA", "BBBB"])
        XCTAssertEqual(lenient.chunks.map(\.data), strict.chunks.map(\.data))
    }

    func testAFileWithoutAnyChunkIsValidInBothModes() throws {
        let empty = AIFFChunks.serialize(formType: "AIFF", chunks: [])

        XCTAssertTrue(try AIFFChunks.parse(empty).chunks.isEmpty)
        XCTAssertTrue(try AIFFChunks.parse(empty, lenient: true).chunks.isEmpty)
    }

    // MARK: - Wrong FORM size

    func testAFormSizeThatIsTooLargeIsOnlyAcceptedLeniently() throws {
        let data = settingFormSize(0x7FFF, in: valid)

        assertStrictRejects(data)
        XCTAssertEqual(try lenientIDs(data), ["AAAA", "BBBB"])
    }

    func testAStreamedFileWithTheMaximumFormSizeIsReadLeniently() throws {
        let data = settingFormSize(0xFFFF_FFFF, in: valid)

        assertStrictRejects(data)
        XCTAssertEqual(try lenientIDs(data), ["AAAA", "BBBB"])
    }

    func testBytesAfterTheFormAreIgnoredLeniently() throws {
        // e.g. an ID3v2 tag that a tagger appended behind the FORM chunk.
        var data = valid
        data.append(Data("ID3".utf8) + Data(repeating: 0x55, count: 20))

        assertStrictRejects(data)
        XCTAssertEqual(try lenientIDs(data), ["AAAA", "BBBB"])
    }

    // MARK: - Damaged chunk structure

    func testAPartialChunkHeaderAtTheEndKeepsTheIntactChunksLeniently() throws {
        let data = consistent(valid + Data([0x53, 0x53, 0x4E]))

        assertStrictRejects(data)
        XCTAssertEqual(try lenientIDs(data), ["AAAA", "BBBB"])
    }

    func testAMissingFinalPadByteIsToleratedLeniently() throws {
        let odd = AIFFChunks.serialize(
            formType: "AIFF",
            chunks: [AIFFChunk(id: "AAAA", data: Data([1, 2, 3]))]
        )
        let withoutPad = consistent(odd.dropLast())

        assertStrictRejects(withoutPad)

        let parsed = try AIFFChunks.parse(withoutPad, lenient: true)
        XCTAssertEqual(parsed.chunks.map(\.id), ["AAAA"])
        XCTAssertEqual(parsed.chunks.first?.data, Data([1, 2, 3]))
    }

    func testACutOffLastChunkIsDroppedButEarlierChunksSurviveLeniently() throws {
        var cut = AIFFChunks.serialize(formType: "AIFF", chunks: [first])
        cut.append(Data("BBBB".utf8))
        cut.append(contentsOf: [0, 0, 0, 100])   // claims 100 bytes
        cut.append(contentsOf: [5, 6])            // only 2 are there
        let data = consistent(cut)

        assertStrictRejects(data)
        XCTAssertEqual(try lenientIDs(data), ["AAAA"])
    }

    // MARK: - Not AIFF at all

    func testDataThatIsNotAIFFIsRejectedInBothModes() {
        let wave = Data("FORM".utf8) + Data([0, 0, 0, 4]) + Data("WAVE".utf8)
        let riff = Data("RIFF".utf8) + valid.dropFirst(4)
        let tooShort = Data("FORM".utf8) + Data([0, 0])

        for data in [wave, riff, tooShort] {
            for lenient in [false, true] {
                XCTAssertThrowsError(try AIFFChunks.parse(data, lenient: lenient)) { error in
                    guard case AIFFParseError.notAIFF = error else {
                        return XCTFail("expected .notAIFF, got \(error)")
                    }
                }
            }
        }
    }
}
