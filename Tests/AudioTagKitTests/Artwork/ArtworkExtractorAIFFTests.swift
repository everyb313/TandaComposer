import XCTest
import Foundation

/// `ArtworkExtractor` for AIFF: the picture lives in an ID3 "APIC" frame
/// inside the file's "ID3 " chunk. (The FLAC path is covered by
/// `ArtworkExtractorTests`.)
final class ArtworkExtractorAIFFTests: XCTestCase {
    private var temporaryDirectory: URL!

    /// A real 1x1 PNG, so ImageIO can report its size.
    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkExtractorAIFFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func apicFrame(mime: String, imageData: Data) -> Data {
        var content = Data([0x00])                       // ISO-8859-1 text
        content.append(contentsOf: Array(mime.utf8))
        content.append(0x00)                             // end of MIME type
        content.append(0x03)                             // picture type: front cover
        content.append(contentsOf: Array("cover".utf8))  // description
        content.append(0x00)
        content.append(imageData)

        return ID3FrameCodec.frame(id: "APIC", content: content)
    }

    private func id3Chunk(_ frames: [Data]) -> AIFFChunk {
        let body = frames.reduce(Data(), +)
        var tag = ID3FrameCodec.header(bodySize: body.count)
        tag.append(body)

        return AIFFChunk(id: "ID3 ", data: tag)
    }

    private func makeAIFF(
        name: String = "artwork.aiff",
        formType: String = "AIFF",
        chunks: [AIFFChunk]
    ) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try AIFFChunks.serialize(formType: formType, chunks: chunks).write(to: url)

        return url
    }

    private let sound = AIFFChunk(id: "SSND", data: Data([0, 0, 0, 0, 0, 0, 0, 0, 1, 2]))

    // MARK: - Tests

    func testExtractsArtworkFromTheAPICFrame() async throws {
        let url = try makeAIFF(chunks: [
            sound,
            id3Chunk([apicFrame(mime: "image/png", imageData: png)])
        ])

        let artwork = try await ArtworkExtractor.extract(from: url)

        let result = try XCTUnwrap(artwork)
        XCTAssertEqual(result.data, png)
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.width, 1)
        XCTAssertEqual(result.height, 1)
    }

    func testExtractsArtworkFromAnAIFCFile() async throws {
        let url = try makeAIFF(
            name: "artwork.aifc",
            formType: "AIFC",
            chunks: [id3Chunk([apicFrame(mime: "image/png", imageData: png)])]
        )

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertEqual(try XCTUnwrap(artwork).data, png)
    }

    func testTheFirstPictureWinsWhenSeveralAreEmbedded() async throws {
        let jpegLike = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let url = try makeAIFF(chunks: [
            id3Chunk([
                apicFrame(mime: "image/png", imageData: png),
                apicFrame(mime: "image/jpeg", imageData: jpegLike)
            ])
        ])

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertEqual(try XCTUnwrap(artwork).data, png)
    }

    func testOtherFramesAroundThePictureDoNotMatter() async throws {
        let url = try makeAIFF(chunks: [
            id3Chunk([
                ID3FrameCodec.textFrame("TIT2", "Title"),
                apicFrame(mime: "image/png", imageData: png),
                ID3FrameCodec.textFrame("TPE1", "Artist")
            ])
        ])

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertEqual(try XCTUnwrap(artwork).mimeType, "image/png")
    }

    func testReturnsNilWhenTheFileHasNoID3Chunk() async throws {
        let url = try makeAIFF(chunks: [sound])

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertNil(artwork)
    }

    func testReturnsNilWhenTheID3ChunkHasNoPicture() async throws {
        let url = try makeAIFF(chunks: [
            id3Chunk([ID3FrameCodec.textFrame("TIT2", "Title")])
        ])

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertNil(artwork)
    }

    func testReturnsNilForAPictureFrameThatCannotBeDecoded() async throws {
        // MIME type without its terminating zero byte.
        var broken = Data([0x00])
        broken.append(contentsOf: Array("image/png".utf8))
        let url = try makeAIFF(chunks: [
            id3Chunk([ID3FrameCodec.frame(id: "APIC", content: broken)])
        ])

        let artwork = try await ArtworkExtractor.extract(from: url)

        XCTAssertNil(artwork)
    }

    func testImageDataThatImageIOCannotReadStillComesBackWithoutSize() async throws {
        let notReallyAnImage = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let url = try makeAIFF(chunks: [
            id3Chunk([apicFrame(mime: "image/jpeg", imageData: notReallyAnImage)])
        ])

        let artwork = try await ArtworkExtractor.extract(from: url)

        let result = try XCTUnwrap(artwork)
        XCTAssertEqual(result.data, notReallyAnImage)
        XCTAssertEqual(result.mimeType, "image/jpeg")
        XCTAssertNil(result.width)
        XCTAssertNil(result.height)
    }
}
