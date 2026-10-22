import XCTest
import Foundation

final class AIFFChunksTests: XCTestCase {
    func testSerializeParseRoundTripPreservesChunkOrderAndPayloads() throws {
        let chunks = [
            AIFFChunk(id: "COMM", data: Data([1, 2, 3])),
            AIFFChunk(id: "SSND", data: Data([0x00, 0x01, 0x02, 0x03])),
            AIFFChunk(id: "XTRA", data: Data([9]))
        ]
        let data = AIFFChunks.serialize(formType: "AIFF", chunks: chunks)
        let parsed = try AIFFChunks.parse(data)

        XCTAssertEqual(parsed.formType, "AIFF")
        XCTAssertEqual(parsed.chunks.map(\.id), chunks.map(\.id))
        XCTAssertEqual(parsed.chunks.map(\.data), chunks.map(\.data))
    }

    func testSupportsAIFCFormType() throws {
        let data = AIFFChunks.serialize(formType: "AIFC", chunks: [
            AIFFChunk(id: "FVER", data: Data([0, 0, 0, 1]))
        ])
        XCTAssertEqual(try AIFFChunks.parse(data).formType, "AIFC")
    }

    func testOddSizedChunksArePaddedAndNextChunkRemainsReadable() throws {
        let data = AIFFChunks.serialize(formType: "AIFF", chunks: [
            AIFFChunk(id: "ODD!", data: Data([0x7F])),
            AIFFChunk(id: "NEXT", data: Data([0x11, 0x22]))
        ])
        let parsed = try AIFFChunks.parse(data)
        XCTAssertEqual(parsed.chunks.map(\.id), ["ODD!", "NEXT"])
        XCTAssertEqual(parsed.chunks[0].data, Data([0x7F]))
        XCTAssertEqual(parsed.chunks[1].data, Data([0x11, 0x22]))
    }

    func testRejectsInvalidFormMarkerAndFormType() {
        XCTAssertThrowsError(try AIFFChunks.parse(Data("NOPE".utf8) + Data(repeating: 0, count: 12)))
        XCTAssertThrowsError(try AIFFChunks.parse(
            Data("FORM".utf8) + Data([0, 0, 0, 4]) + Data("WAVE".utf8)
        ))
    }

    func testRejectsChunkLengthBeyondEndOfFile() {
        let data = Data("FORM".utf8) + Data([0, 0, 0, 12]) + Data("AIFF".utf8)
            + Data("SSND".utf8) + Data([0, 0, 0, 8, 0x01, 0x02])
        XCTAssertThrowsError(try AIFFChunks.parse(data))
    }
}
