import XCTest
import Foundation

final class ArtworkExtractorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkExtractorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testExtractsArtworkFromFLACPictureBlock() async throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xD9]) // tiny JPEG-signature fixture
        let picture = makePictureBlock(mime: "image/jpeg", width: 120, height: 80, imageData: image)
        let fileData = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data([0, 0, 0])),
                FLACBlock(type: FLACBlocks.picture, data: picture)
            ],
            audioData: Data([0xFF, 0xF8])
        )
        let url = temporaryDirectory.appendingPathComponent("artwork.flac")
        try fileData.write(to: url)

        let artwork = try await ArtworkExtractor.extract(from: url)
        let result = try XCTUnwrap(artwork)
        XCTAssertEqual(result.data, image)
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertEqual(result.width, 120)
        XCTAssertEqual(result.height, 80)
    }

    func testReturnsNilWhenFLACHasNoPictureBlock() async throws {
        let fileData = FLACBlocks.serialize(
            blocks: [FLACBlock(type: FLACBlocks.streamInfo, data: Data([1, 2, 3]))],
            audioData: Data([0xFF, 0xF8])
        )
        let url = temporaryDirectory.appendingPathComponent("no-artwork.flac")
        try fileData.write(to: url)

        let artwork = try await ArtworkExtractor.extract(from: url)
        XCTAssertNil(artwork)
    }

    func testThrowsForTruncatedFLACPictureBlock() async throws {
        let fileData = FLACBlocks.serialize(
            blocks: [
                FLACBlock(type: FLACBlocks.streamInfo, data: Data([1])),
                FLACBlock(type: FLACBlocks.picture, data: Data([0, 0, 0, 3, 0]))
            ],
            audioData: Data()
        )
        let url = temporaryDirectory.appendingPathComponent("truncated-artwork.flac")
        try fileData.write(to: url)

        do {
            _ = try await ArtworkExtractor.extract(from: url)
            XCTFail("Expected a truncated picture block to throw.")
        } catch {
            XCTAssertTrue(error is FLACParseError)
        }
    }

    private func makePictureBlock(
        mime: String,
        width: Int,
        height: Int,
        imageData: Data
    ) -> Data {
        var block = Data()
        appendBE(3, to: &block) // front cover
        appendString(mime, to: &block)
        appendString("", to: &block) // description
        appendBE(width, to: &block)
        appendBE(height, to: &block)
        appendBE(24, to: &block) // color depth
        appendBE(0, to: &block)  // indexed colors
        appendBE(imageData.count, to: &block)
        block.append(imageData)
        return block
    }

    private func appendString(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        appendBE(bytes.count, to: &data)
        data.append(bytes)
    }

    private func appendBE(_ value: Int, to data: inout Data) {
        let v = UInt32(value)
        data.append(contentsOf: [
            UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
            UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)
        ])
    }
}
